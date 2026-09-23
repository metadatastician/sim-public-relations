#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="${root}/.github/workflows/dogfood-gate.yml"
lock="${root}/.github/workflows/actions.lock"
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT
total=0

assert_equal() {
  local label="$1" expected="$2" actual="$3"
  total=$((total + 1))
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'not ok %d - %s\nexpected: %s\nactual: %s\n' "${total}" "${label}" "${expected}" "${actual}" >&2
    exit 1
  fi
  printf 'ok %d - %s\n' "${total}" "${label}"
}

assert_contains() {
  local label="$1" text="$2" file="$3"
  total=$((total + 1))
  if ! grep -Fq -- "${text}" "${file}"; then
    printf 'not ok %d - %s: missing %s\n' "${total}" "${label}" "${text}" >&2
    exit 1
  fi
  printf 'ok %d - %s\n' "${total}" "${label}"
}

assert_absent() {
  local label="$1" text="$2" file="$3"
  total=$((total + 1))
  if grep -Fq -- "${text}" "${file}"; then
    printf 'not ok %d - %s: found %s\n' "${total}" "${label}" "${text}" >&2
    exit 1
  fi
  printf 'ok %d - %s\n' "${total}" "${label}"
}

assert_absent 'retired validation job is removed' '  a2ml-validate:' "${workflow}"
assert_absent 'retired validation action is removed' 'hyperpolymath/a2ml-ecosystem' "${workflow}"
assert_absent 'retired format is not scored' 'A2ML' "${workflow}"

needs="$(awk '
  /^  dogfood-summary:$/ { in_summary = 1; next }
  in_summary && /^  [a-zA-Z0-9_-]+:/ { exit }
  in_summary && /^    needs:/ { sub(/^    needs: /, ""); print; exit }
' "${workflow}")"
assert_equal 'summary waits for exactly the four surviving jobs' \
  '[k9-validate, empty-lint, groove-check, eclexiaiser-validate]' "${needs}"
assert_contains 'summary still runs if a prerequisite fails' '    if: always()' "${workflow}"

locked_refs="$(awk -v key="    '.github/workflows/dogfood-gate.yml':" '
  $0 == key { in_entry = 1; found = 1; next }
  in_entry && /^    [^ ]/ { exit }
  in_entry && /^        - / { print }
  END { if (!found) exit 1 }
' "${lock}")"
assert_equal 'workflow lock lists only surviving actions' \
  "$(printf "        - 'actions/checkout@v7.0.1'\n        - 'hyperpolymath/k9-ecosystem@main'")" \
  "${locked_refs}"
assert_absent 'retired action has no orphaned dependency record' \
  "    'hyperpolymath/a2ml-ecosystem@main':" "${lock}"

scorecard="${scratch}/scorecard.sh"
awk '
  $0 == "      - name: Generate dogfooding scorecard" { step = 1; next }
  step && $0 == "        run: |" { script = 1; next }
  script && /^          / { sub(/^          /, ""); print; next }
  script && /^$/ { print; next }
  script { exit }
  END { if (!script) exit 1 }
' "${workflow}" > "${scorecard}"
bash -n "${scorecard}"

run_scorecard() {
  local label="$1"
  local case_dir="${scratch}/${label}"
  local summary="${scratch}/${label}.md"
  mkdir -p "${case_dir}"
  (cd "${case_dir}" && GITHUB_STEP_SUMMARY="${summary}" bash "${scorecard}")
}

run_scorecard empty
assert_contains 'empty repository scores zero out of five' '**Score: 0/5**' "${scratch}/empty.md"
assert_equal 'scorecard has exactly five tool rows' 6 "$(grep -c '^| ' "${scratch}/empty.md")"
assert_equal 'missing required formats are marked absent' 2 "$(grep -o ':x:' "${scratch}/empty.md" | wc -l | tr -d ' ')"
assert_equal 'missing optional integrations are marked optional' 3 "$(grep -o ':ballot_box_with_check:' "${scratch}/empty.md" | wc -l | tr -d ' ')"

mkdir -p "${scratch}/retired-only"
touch "${scratch}/retired-only/0-AI-MANIFEST.a2ml"
run_scorecard retired-only
assert_equal 'an A2ML manifest cannot change the score or add a row' \
  "$(cat "${scratch}/empty.md")" "$(cat "${scratch}/retired-only.md")"

mkdir -p "${scratch}/partial"
touch "${scratch}/partial/.editorconfig" "${scratch}/partial/contract.k9"
run_scorecard partial
assert_contains 'required formats independently earn points' '**Score: 2/5**' "${scratch}/partial.md"
assert_contains 'K9 result appears in the scorecard' '| K9 contracts | :white_check_mark: |' "${scratch}/partial.md"
assert_contains 'editorconfig result appears in the scorecard' '| .editorconfig | :white_check_mark: |' "${scratch}/partial.md"

mkdir -p "${scratch}/complete/.well-known/groove"
touch "${scratch}/complete/contract.k9" "${scratch}/complete/.editorconfig" \
  "${scratch}/complete/.well-known/groove/manifest.json" "${scratch}/complete/eclexiaiser.toml"
printf '%s\n' 'database = "VeriSimDB"' > "${scratch}/complete/state.toml"
run_scorecard complete
assert_contains 'all five active checks earn points' '**Score: 5/5**' "${scratch}/complete.md"
assert_equal 'every active row is marked present' 5 "$(grep -o ':white_check_mark:' "${scratch}/complete.md" | wc -l | tr -d ' ')"

printf 'PASS dogfood gate tests: %d/%d\n' "${total}" "${total}"
