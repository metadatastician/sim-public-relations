#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Regression tests for the foundation CI/CD security posture (#23, #26, #28).
#
# These assert PROPERTIES, not snapshots. The previous version of this file
# (and its sibling foundation_ci_fixes_test.sh) hard-coded the exact SHAs PR
# #26 wrote, and so "passed" while three of those SHAs did not exist in
# hyperpolymath/standards, the lock marker it demanded on line 1 had pushed
# every SPDX header off line 1, and actions.lock had been left behind. A test
# that can only agree with the file it is testing enforces nothing. Each
# property below is one that #26 or #28 violated and that CI then measured as
# a real failure on main.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
wf="${root}/.github/workflows"
lock="${wf}/actions.lock"
codeql="${wf}/codeql.yml"

passes=0
total=0

pass() { passes=$((passes + 1)); printf 'ok %d - %s\n' "${total}" "$1"; }
fail() { printf 'not ok %d - %s\n%s\n' "${total}" "$1" "$2" >&2; exit 1; }

check() {
  # check LABEL CMD... — CMD's stdout/stderr is the failure detail.
  local label="$1"; shift
  local out
  total=$((total + 1))
  if ! out="$("$@" 2>&1)"; then
    fail "${label}" "${out}"
  fi
  pass "${label}"
}

# owner/repo[/path]@ref -> owner/repo@ref, lowercased on owner/repo only (the
# same normalisation scripts/check-lock-sync.sh applies).
norm() {
  local r="$1" path ref
  path="${r%@*}"; ref="${r##*@}"
  path="$(printf '%s' "${path}" | cut -d/ -f1-2 | tr '[:upper:]' '[:lower:]')"
  printf '%s@%s\n' "${path}" "${ref}"
}

uses_refs() {
  sed -nE 's/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*["'"'"']?([^[:space:]#"'"'"']+).*/\2/p' "$1"
}

# ---------------------------------------------------------------------------
# 1. Header discipline: SPDX is line 1 of every workflow. The repo's own
#    Workflow Security Linter checks exactly `head -1`; #26 broke all 25.
spdx_first_line() {
  local f bad=0
  for f in "${wf}"/*.yml "${wf}"/*.yaml; do
    [ -f "${f}" ] || continue
    if ! head -1 "${f}" | grep -q '^# SPDX-License-Identifier:'; then
      printf '%s: line 1 is not an SPDX header\n' "${f#"${root}"/}"; bad=1
    fi
    if [ "$(grep -c '^# This workflow is managed by gh actions-lock\.$' "${f}")" -gt 1 ]; then
      printf '%s: duplicated actions-lock banner\n' "${f#"${root}"/}"; bad=1
    fi
  done
  return "${bad}"
}
check 'every workflow has its SPDX header on line 1 and at most one lock banner' spdx_first_line

# ---------------------------------------------------------------------------
# 2. Lockfile coverage: every uses: ref is either an inline 40-hex SHA or is
#    resolvable through actions.lock, and every reusable-workflow pin in the
#    lock is a record, not a dangling edge. This is the property whose loss
#    puts a workflow into startup_failure with zero jobs (#22, #23).
lock_covers_every_ref() {
  local f key r n bad=0
  [ -f "${lock}" ] || { echo "no actions.lock"; return 1; }
  for f in "${wf}"/*.yml "${wf}"/*.yaml; do
    [ -f "${f}" ] || continue
    key=".github/workflows/$(basename "${f}")"
    grep -Fq "'${key}':" "${lock}" \
      || { printf '%s: no key in actions.lock (unlisted workflow)\n' "${key}"; bad=1; }
    while IFS= read -r r; do
      [ -n "${r}" ] || continue
      case "${r}" in ./*|\$/*|docker://*) continue ;; esac
      n="$(norm "${r}")"
      grep -Fq -- "- '${n}'" "${lock}" \
        || { printf '%s: %s is not recorded in actions.lock\n' "${key}" "${r}"; bad=1; }
      grep -Fq -- "    '${n}':" "${lock}" \
        || { printf '%s: %s has no dependencies: record (dangling edge)\n' "${key}" "${n}"; bad=1; }
    done < <(uses_refs "${f}")
  done
  return "${bad}"
}
check 'every uses: ref is recorded in actions.lock with a resolvable record' lock_covers_every_ref

# ---------------------------------------------------------------------------
# 3. Shared standards revision: all hyperpolymath/standards reusable-workflow
#    callers pin ONE 40-hex commit. #26 spread three different, non-existent
#    SHAs across three files. One revision means one thing to verify and one
#    lockfile record to keep closed.
single_standards_revision() {
  local shas
  shas="$(grep -hoE 'hyperpolymath/standards/\.github/workflows/[a-z-]+\.yml@[^[:space:]#]+' "${wf}"/*.yml \
          | sed 's/.*@//' | sort -u)"
  [ -n "${shas}" ] || { echo "no standards reusable-workflow callers found"; return 1; }
  if [ "$(printf '%s\n' "${shas}" | wc -l)" -ne 1 ]; then
    printf 'callers pin more than one standards revision:\n%s\n' "${shas}"; return 1
  fi
  [[ "${shas}" =~ ^[0-9a-f]{40}$ ]] \
    || { printf 'standards pin is not a full lowercase commit SHA: %s\n' "${shas}"; return 1; }
  grep -Fq "    'hyperpolymath/standards@${shas}':" "${lock}" \
    || { printf 'actions.lock has no dependencies: record for standards@%s\n' "${shas}"; return 1; }
}
check 'all standards reusable-workflow callers pin one SHA that actions.lock records' single_standards_revision

# The three revisions #26 introduced do not exist in hyperpolymath/standards
# (GitHub API: "No commit found for SHA"). They must never come back.
forged_pins_absent() {
  ! grep -rnE '8f31a5a4ba591d544b65f91f6d78b136e07756f0|cc58c0cb23f73fc2019ce85a56a468e5248a93b3|8750b94ac1bbe8c51ad13fe106669b13478f0b62' \
      "${wf}" "${root}/tests" --exclude="$(basename "${BASH_SOURCE[0]}")"
}
check 'the forged standards revisions from #26 are gone' forged_pins_absent

# ---------------------------------------------------------------------------
# 4. CodeQL: safe checkout, init/analyze in lockstep, and never the release
#    GitHub refuses at startup (4.38.1 — hyperpolymath/nexia-list#100 — which
#    is what #28 bumped onto, tag 1c5b6756).
codeql_posture() {
  local init analyze bad=0
  grep -Fq 'persist-credentials: false' "${codeql}" \
    || { echo 'codeql checkout must set persist-credentials: false'; bad=1; }
  ! grep -Fq 'persist-credentials: true' "${codeql}" \
    || { echo 'codeql checkout must not persist credentials'; bad=1; }
  init="$(uses_refs "${codeql}" | grep '^github/codeql-action/init@' | sed 's/.*@//')"
  analyze="$(uses_refs "${codeql}" | grep '^github/codeql-action/analyze@' | sed 's/.*@//')"
  [ -n "${init}" ] && [ -n "${analyze}" ] \
    || { echo 'codeql must call both init and analyze'; bad=1; }
  [ "${init}" = "${analyze}" ] \
    || { printf 'codeql init (%s) and analyze (%s) drift\n' "${init}" "${analyze}"; bad=1; }
  ! grep -qE 'codeql-action/[a-z-]+@(v?4\.38\.1|1c5b675653bb5c22dbe9b12b556ec555138e09fd)' "${codeql}" \
    || { echo 'codeql-action 4.38.1 is refused by GitHub at startup (nexia-list#100)'; bad=1; }
  grep -Fq 'dependency-name: "github/codeql-action"' "${root}/.github/dependabot.yml" \
    && grep -Fq '"4.38.1"' "${root}/.github/dependabot.yml" \
    || { echo 'dependabot.yml must ignore github/codeql-action 4.38.1'; bad=1; }
  return "${bad}"
}
check 'CodeQL: credentials not persisted, init/analyze in lockstep, 4.38.1 excluded' codeql_posture

# ---------------------------------------------------------------------------
# 5. No spoofable bot-identity gates (Hypatia RE008, critical). github.actor is
#    the run-triggering user, attacker-controlled on pull_request_target.
no_actor_bot_gates() {
  ! grep -rnE "github\.actor[[:space:]]*(==|!=)[[:space:]]*['\"][A-Za-z0-9_-]+\[bot\]['\"]" "${wf}"
}
check 'no workflow gates trust on github.actor == "<something>[bot]"' no_actor_bot_gates

# ---------------------------------------------------------------------------
# 6. No banned-language sources in the tree (Hypatia critical; governance
#    language policy). The mint helpers are Rust now (scripts/*.rs).
no_python_sources() {
  local py
  py="$(cd "${root}" && git ls-files '*.py' 2>/dev/null || true)"
  [ -z "${py}" ] || { printf 'Python files are banned estate-wide:\n%s\n' "${py}"; return 1; }
  [ -f "${root}/scripts/strip-instruction-blocks.rs" ] \
    && [ -f "${root}/scripts/prune-dependabot-ecosystems.rs" ] \
    && [ -f "${root}/scripts/rust-tool.sh" ] \
    || { echo 'the Rust mint tools (and scripts/rust-tool.sh) must be present'; return 1; }
  # rust-tool.sh is invoked as `bash scripts/rust-tool.sh` (repo-init.just), so
  # its mode bit is not load-bearing and is not asserted: commits authored
  # through GitHub's signing API cannot set modes.
}
check 'no Python in the tree; the mint tools are the Rust ports' no_python_sources

# ---------------------------------------------------------------------------
# Negative fixtures: prove the properties fail closed rather than merely
# agreeing with the current files.
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT
mkdir -p "${scratch}/.github/workflows"

expect_reject() {
  local label="$1"; shift
  total=$((total + 1))
  if "$@" >/dev/null 2>&1; then
    fail "${label}" 'expected the check to fail, it passed'
  fi
  pass "${label}"
}

wf_saved="${wf}"; lock_saved="${lock}"; codeql_saved="${codeql}"

wf="${scratch}/.github/workflows"; lock="${wf}/actions.lock"; codeql="${wf}/codeql.yml"
cp "${wf_saved}"/*.yml "${wf_saved}/actions.lock" "${wf}/"
{ echo '# This workflow is managed by gh actions-lock.'; cat "${codeql_saved}"; } > "${codeql}"
expect_reject 'rejects a banner that displaces the SPDX header' spdx_first_line

cp "${codeql_saved}" "${codeql}"
sed -i 's|codeql-action/analyze@[^[:space:]#]*|codeql-action/analyze@v4.38.1|' "${codeql}"
expect_reject 'rejects codeql-action 4.38.1' codeql_posture
expect_reject 'rejects init/analyze drift' codeql_posture

cp "${codeql_saved}" "${codeql}"
sed -i 's|uses: github/codeql-action/init@.*|uses: github/codeql-action/init@v0.0.0-unlocked|' "${codeql}"
expect_reject 'rejects a uses: ref that actions.lock does not record' lock_covers_every_ref

cp "${codeql_saved}" "${codeql}"
sed -i 's|governance-reusable.yml@[0-9a-f]\{40\}|governance-reusable.yml@8f31a5a4ba591d544b65f91f6d78b136e07756f0|' "${wf}/governance.yml"
expect_reject 'rejects a second (and forged) standards revision' single_standards_revision

cp "${wf_saved}/governance.yml" "${wf}/governance.yml"
printf '    if: github.actor == %s\n' "'dependabot[bot]'" >> "${wf}/labels.yml"
expect_reject 'rejects a github.actor bot gate' no_actor_bot_gates

wf="${wf_saved}"; lock="${lock_saved}"; codeql="${codeql_saved}"

printf 'PASS foundation CI security tests: %d/%d\n' "${passes}" "${total}"
