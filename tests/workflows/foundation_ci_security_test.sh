#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Regression tests for the foundation CI/CD security hardening in PR #26.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

checkout_sha="3d3c42e5aac5ba805825da76410c181273ba90b1"
codeql_sha="cdf488f595d80d6e07e03d4674febd5ab45fa938"
governance_sha="8f31a5a4ba591d544b65f91f6d78b136e07756f0"
hypatia_sha="cc58c0cb23f73fc2019ce85a56a468e5248a93b3"
scorecard_sha="8750b94ac1bbe8c51ad13fe106669b13478f0b62"

passes=0
total=0
status=0
output=""

pass() {
  passes=$((passes + 1))
  printf 'ok %d - %s\n' "${total}" "$1"
}

fail() {
  printf 'not ok %d - %s\n%s\n' "${total}" "$1" "$2" >&2
  exit 1
}

run_check() {
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
}

expect_accept() {
  local label="$1"
  shift
  total=$((total + 1))
  run_check "$@"
  if [ "${status}" -ne 0 ]; then
    fail "${label}" "expected success, got ${status}: ${output}"
  fi
  pass "${label}"
}

expect_reject() {
  local label="$1" expected="$2"
  shift 2
  total=$((total + 1))
  run_check "$@"
  if [ "${status}" -eq 0 ]; then
    fail "${label}" "expected failure, got success"
  fi
  if [[ "${output}" != *"${expected}"* ]]; then
    fail "${label}" "failure did not contain '${expected}': ${output}"
  fi
  pass "${label}"
}

workflow_refs() {
  sed -n 's/^[[:space:]]*uses:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$1"
}

checkout_step() {
  awk '
    $0 == "      - name: Checkout" { found = 1; print; next }
    found && /^      - name:/ { exit }
    found { print }
    END { if (!found) exit 1 }
  ' "$1"
}

validate_codeql() {
  local file="$1" checkout_block
  local -a actual_refs expected_refs

  mapfile -t actual_refs < <(workflow_refs "${file}")
  expected_refs=(
    "actions/checkout@${checkout_sha}"
    "github/codeql-action/init@${codeql_sha}"
    "github/codeql-action/analyze@${codeql_sha}"
  )

  if [ "${#actual_refs[@]}" -ne "${#expected_refs[@]}" ]; then
    printf 'CodeQL workflow must have exactly three action references\n' >&2
    return 1
  fi

  local index
  for index in "${!expected_refs[@]}"; do
    if [ "${actual_refs[${index}]}" != "${expected_refs[${index}]}" ]; then
      printf 'unexpected action reference at position %d: %s\n' \
        "$((index + 1))" "${actual_refs[${index}]}" >&2
      return 1
    fi
    if [[ ! "${actual_refs[${index}]}" =~ @[0-9a-f]{40}$ ]]; then
      printf 'action reference is not pinned to a full lowercase SHA: %s\n' \
        "${actual_refs[${index}]}" >&2
      return 1
    fi
  done

  if ! checkout_block="$(checkout_step "${file}")"; then
    printf 'CodeQL workflow must retain a named Checkout step\n' >&2
    return 1
  fi
  if ! grep -Fqx "        uses: actions/checkout@${checkout_sha} # v7.0.1" <<<"${checkout_block}"; then
    printf 'checkout pin must remain in the Checkout step\n' >&2
    return 1
  fi
  if ! grep -Fqx '          persist-credentials: false' <<<"${checkout_block}"; then
    printf 'checkout must disable persisted credentials in its own with block\n' >&2
    return 1
  fi
}

validate_reusable() {
  local file="$1" workflow="$2" expected_sha="$3"
  local expected="hyperpolymath/standards/.github/workflows/${workflow}@${expected_sha}"
  local -a refs

  mapfile -t refs < <(workflow_refs "${file}")
  if [ "${#refs[@]}" -ne 1 ]; then
    printf 'reusable workflow caller must contain exactly one uses reference\n' >&2
    return 1
  fi
  if [ "${refs[0]}" != "${expected}" ]; then
    printf 'unexpected reusable workflow reference: %s\n' "${refs[0]}" >&2
    return 1
  fi
  if [[ ! "${refs[0]}" =~ @[0-9a-f]{40}$ ]]; then
    printf 'reusable workflow is not pinned to a full lowercase SHA\n' >&2
    return 1
  fi
}

codeql="${root}/.github/workflows/codeql.yml"
governance="${root}/.github/workflows/governance.yml"
hypatia="${root}/.github/workflows/hypatia-scan.yml"
scorecard="${root}/.github/workflows/scorecard.yml"

expect_accept 'CodeQL actions use the approved immutable pins and safe checkout' \
  validate_codeql "${codeql}"
expect_accept 'governance calls the approved reusable workflow revision' \
  validate_reusable "${governance}" governance-reusable.yml "${governance_sha}"
expect_accept 'Hypatia calls the approved reusable workflow revision' \
  validate_reusable "${hypatia}" hypatia-scan-reusable.yml "${hypatia_sha}"
expect_accept 'scorecard calls the approved reusable workflow revision' \
  validate_reusable "${scorecard}" scorecard-reusable.yml "${scorecard_sha}"

# Negative fixtures prove the checks fail closed on the regressions this change
# is intended to prevent, instead of merely matching the current files.
sed "s|actions/checkout@${checkout_sha}|actions/checkout@v7.0.1|" \
  "${codeql}" > "${scratch}/codeql-tag.yml"
expect_reject 'CodeQL rejects a mutable checkout tag' 'unexpected action reference' \
  validate_codeql "${scratch}/codeql-tag.yml"

sed 's/persist-credentials: false/persist-credentials: true/' \
  "${codeql}" > "${scratch}/codeql-credentials.yml"
expect_reject 'CodeQL rejects persisted checkout credentials' \
  'checkout must disable persisted credentials' \
  validate_codeql "${scratch}/codeql-credentials.yml"

sed '/github\/codeql-action\/analyze@/d' \
  "${codeql}" > "${scratch}/codeql-missing-analysis.yml"
expect_reject 'CodeQL rejects loss of the analysis action' \
  'exactly three action references' \
  validate_codeql "${scratch}/codeql-missing-analysis.yml"

sed "s|@${governance_sha}|@main|" \
  "${governance}" > "${scratch}/governance-tag.yml"
expect_reject 'reusable workflows reject mutable branch references' \
  'unexpected reusable workflow reference' \
  validate_reusable "${scratch}/governance-tag.yml" governance-reusable.yml "${governance_sha}"

sed "s|@${hypatia_sha}|@bd0df9ead7faf0cdfe0e13e7966d91e28d0101d4|" \
  "${hypatia}" > "${scratch}/hypatia-stale.yml"
expect_reject 'Hypatia rejects the superseded shared standards revision' \
  'unexpected reusable workflow reference' \
  validate_reusable "${scratch}/hypatia-stale.yml" hypatia-scan-reusable.yml "${hypatia_sha}"

sed 's|governance-reusable.yml|scorecard-reusable.yml|' \
  "${governance}" > "${scratch}/governance-wrong-workflow.yml"
expect_reject 'reusable callers reject a valid SHA on the wrong workflow path' \
  'unexpected reusable workflow reference' \
  validate_reusable "${scratch}/governance-wrong-workflow.yml" governance-reusable.yml "${governance_sha}"

printf 'PASS foundation CI security tests: %d/%d\n' "${passes}" "${total}"
