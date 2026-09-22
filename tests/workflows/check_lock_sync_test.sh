#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Unit and regression tests for scripts/check-lock-sync.sh and its gate workflow.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
validator="${root}/scripts/check-lock-sync.sh"
gate="${root}/.github/workflows/lock-sync-gate.yml"
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

passes=0
total=0
case_dir=""
status=0
output=""

new_case() {
  case_dir="${scratch}/$1"
  mkdir -p "${case_dir}"
}

write_workflow() {
  local name="$1" content="$2"
  printf '%s\n' "${content}" > "${case_dir}/${name}"
}

write_lock() {
  printf '%s\n' "$1" > "${case_dir}/actions.lock"
}

run_case() {
  set +e
  output="$("${validator}" "${case_dir}" 2>&1)"
  status=$?
  set -e
}

pass() {
  passes=$((passes + 1))
  printf 'ok %d - %s\n' "${total}" "$1"
}

fail() {
  printf 'not ok %d - %s\n' "${total}" "$1" >&2
  printf '%s\n' "$2" >&2
  exit 1
}

expect_pass() {
  local label="$1" expected="$2"
  total=$((total + 1))
  run_case
  if [ "${status}" -ne 0 ]; then
    fail "${label}" "expected success, got ${status}: ${output}"
  fi
  if [[ "${output}" != *"${expected}"* ]]; then
    fail "${label}" "output did not contain '${expected}': ${output}"
  fi
  pass "${label}"
}

expect_fail() {
  local label="$1" expected="$2"
  total=$((total + 1))
  run_case
  if [ "${status}" -eq 0 ]; then
    fail "${label}" "expected failure, got success: ${output}"
  fi
  if [[ "${output}" != *"${expected}"* ]]; then
    fail "${label}" "output did not contain '${expected}': ${output}"
  fi
  pass "${label}"
}

expect_file_contains() {
  local label="$1" pattern="$2"
  total=$((total + 1))
  if ! grep -Eq -- "${pattern}" "${gate}"; then
    fail "${label}" "${gate} did not match: ${pattern}"
  fi
  pass "${label}"
}

expect_file_excludes() {
  local label="$1" pattern="$2"
  total=$((total + 1))
  if grep -Eq -- "${pattern}" "${gate}"; then
    fail "${label}" "${gate} unexpectedly matched: ${pattern}"
  fi
  pass "${label}"
}

# A realistic clean fixture exercises both workflow extensions, action subpath
# normalization, job-level reusable workflows, comments, quotes, duplicates,
# local actions, Docker actions, and case-insensitive owner/repository matching.
new_case clean
write_workflow build.yaml $'name: Build\njobs:\n  local:\n    steps:\n      - uses: ./local/action\n      - uses: docker://alpine:3.22\n      - uses: "Acme/Widget/sub/action@Release" # pinned\n      - uses: acme/widget/sub/action@Release\n  shared:\n    uses: ACME/Reusable/.github/workflows/build.yml@v1'
write_workflow empty.yml $'name: Empty\njobs: {}'
write_lock "$(cat <<'LOCK'
version: 'v0.0.2'
workflows:
    '.github/workflows/build.yaml':
        - 'acme/widget@Release'
        - 'acme/reusable@v1'
    '.github/workflows/empty.yml': []
dependencies:
    'ACME/Widget@Release':
        ref: 'Release'
    'acme/reusable@v1':
        ref: 'v1'
    'unused/tool@v3':
        ref: 'v3'
LOCK
)"
expect_pass "accepts synchronized normalized references" "unreferenced - harmless, but prunable"

new_case missing-lock
write_workflow ci.yml $'name: CI\njobs: {}'
expect_fail "rejects a missing lockfile" "FATAL: no lockfile"

new_case no-workflows
write_lock $'version: '\''v0.0.2'\''\nworkflows:\ndependencies:'
expect_fail "rejects a directory without workflows" "FATAL: no workflow files"

new_case not-onboarded
write_workflow ci.yml $'jobs:\n  test:\n    steps:\n      - uses: acme/widget@v1'
write_lock $'version: '\''v0.0.2'\''\nworkflows:\ndependencies:\n    '\''acme/widget@v1'\'':\n        ref: '\''v1'\'''
expect_fail "reports workflows absent from the lockfile" "not onboarded: no lockfile entry"

new_case missing-ref
write_workflow ci.yml $'jobs:\n  test:\n    steps:\n      - uses: acme/widget@v2'
write_lock $'version: '\''v0.0.2'\''\nworkflows:\n    '\''.github/workflows/ci.yml'\'':\n        - '\''acme/widget@v1'\''\ndependencies:\n    '\''acme/widget@v1'\'':\n        ref: '\''v1'\''\n    '\''acme/widget@v2'\'':\n        ref: '\''v2'\'''
expect_fail "reports a changed workflow reference" "refs missing from the lockfile: acme/widget@v2"

# GitHub compares the ref strings literally at workflow startup. A tag that
# happens to dereference to this SHA is therefore still invalid in the lockfile.
new_case literal-ref
write_workflow ci.yml $'jobs:\n  test:\n    steps:\n      - uses: acme/widget@0123456789abcdef0123456789abcdef01234567'
write_lock $'version: '\''v0.0.2'\''\nworkflows:\n    '\''.github/workflows/ci.yml'\'':\n        - '\''acme/widget@v4.38.0'\''\ndependencies:\n    '\''acme/widget@v4.38.0'\'':\n        ref: '\''v4.38.0'\''\n    '\''acme/widget@0123456789abcdef0123456789abcdef01234567'\'':\n        ref: '\''0123456789abcdef0123456789abcdef01234567'\'''
expect_fail "rejects a tag lock entry for a SHA-pinned workflow" "refs missing from the lockfile: acme/widget@0123456789abcdef0123456789abcdef01234567"

new_case stale-ref
write_workflow ci.yml $'jobs:\n  test:\n    steps:\n      - uses: acme/widget@v1'
write_lock $'version: '\''v0.0.2'\''\nworkflows:\n    '\''.github/workflows/ci.yml'\'':\n        - '\''acme/widget@v1'\''\n        - '\''acme/old@v1'\''\ndependencies:\n    '\''acme/widget@v1'\'':\n        ref: '\''v1'\''\n    '\''acme/old@v1'\'':\n        ref: '\''v1'\'''
expect_fail "reports stale per-workflow lock entries" "stale lockfile entries, no uses: references them: acme/old@v1"

new_case deleted-workflow
write_workflow current.yml $'name: Current\njobs: {}'
write_lock $'version: '\''v0.0.2'\''\nworkflows:\n    '\''.github/workflows/current.yml'\'': []\n    '\''.github/workflows/deleted.yml'\'': []\ndependencies:'
expect_fail "reports lock entries for deleted workflows" "lockfile entry for a workflow file that does not exist"

new_case workflow-dangling
write_workflow ci.yml $'jobs:\n  test:\n    steps:\n      - uses: acme/widget@v1'
write_lock $'version: '\''v0.0.2'\''\nworkflows:\n    '\''.github/workflows/ci.yml'\'':\n        - '\''acme/widget@v1'\''\ndependencies:'
expect_fail "rejects dangling workflow dependencies" "named by: .github/workflows/ci.yml"

new_case nested-dangling
write_workflow ci.yml $'jobs:\n  test:\n    steps:\n      - uses: acme/composite@v1'
write_lock $'version: '\''v0.0.2'\''\nworkflows:\n    '\''.github/workflows/ci.yml'\'':\n        - '\''acme/composite@v1'\''\ndependencies:\n    '\''acme/composite@v1'\'':\n        ref: '\''v1'\''\n        uses:\n            - '\''acme/leaf@sha123'\'''
expect_fail "rejects dangling nested dependencies" "named by: dependencies:acme/composite@v1"

new_case transitively-closed
write_workflow ci.yml $'jobs:\n  test:\n    steps:\n      - uses: acme/composite@v1'
write_lock $'version: '\''v0.0.2'\''\nworkflows:\n    '\''.github/workflows/ci.yml'\'':\n        - '\''acme/composite@v1'\''\ndependencies:\n    '\''acme/composite@v1'\'':\n        ref: '\''v1'\''\n        uses:\n            - '\''acme/leaf@sha123'\''\n    '\''acme/leaf@sha123'\'':\n        ref: '\''sha123'\'''
expect_pass "accepts a transitively closed dependency graph" "0 dangling edges"

new_case corrupt-local
write_workflow ci.yml $'jobs:\n  test:\n    steps:\n      - uses: $/local/action'
write_lock $'version: '\''v0.0.2'\''\nworkflows:\n    '\''.github/workflows/ci.yml'\'': []\ndependencies:'
expect_fail "rejects actions-lock local path corruption" "invalid local-action rewrite (uses: $/...)"

new_case ref-case
write_workflow ci.yml $'jobs:\n  test:\n    steps:\n      - uses: Acme/Widget@Release'
write_lock $'version: '\''v0.0.2'\''\nworkflows:\n    '\''.github/workflows/ci.yml'\'':\n        - '\''acme/widget@release'\''\ndependencies:\n    '\''acme/widget@Release'\'':\n        ref: '\''Release'\''\n    '\''acme/widget@release'\'':\n        ref: '\''release'\'''
expect_fail "keeps case-sensitive refs distinct" "refs missing from the lockfile: Acme/Widget@Release"

# The regenerated lockfile itself is part of the PR and should satisfy the new
# validator, guarding against fixture-only confidence.
case_dir="${root}/.github/workflows"
expect_pass "accepts the pull request's regenerated lockfile" "0 dangling edges"

# Structural regressions in the gate can disable the validator before it runs.
total=$((total + 1))
if [ ! -x "${validator}" ]; then
  fail "validator remains executable" "${validator} is not executable"
fi
pass "validator remains executable"

expect_file_excludes "gate has no action or reusable-workflow dependencies" '^[[:space:]]*(-[[:space:]]*)?uses:'
expect_file_excludes "gate has no path filter" '^[[:space:]]*paths(-ignore)?:'
expect_file_excludes "gate cannot silently tolerate validator failure" 'continue-on-error:'
expect_file_contains "gate runs for pull requests" '^[[:space:]]*pull_request:'
expect_file_contains "gate runs for pushes to main" '^[[:space:]]*branches:[[:space:]]*\[main\]'
expect_file_contains "gate has least-privilege content access" '^[[:space:]]*contents:[[:space:]]*read'
expect_file_contains "gate validates the exact pull request head" 'github\.event\.pull_request\.head\.sha[[:space:]]*\|\|[[:space:]]*github\.sha'
expect_file_contains "gate checks validator executability" 'test -x scripts/check-lock-sync\.sh'
expect_file_contains "gate invokes the validator" '^([[:space:]]*)\./scripts/check-lock-sync\.sh[[:space:]]*$'

printf 'PASS lock-sync tests: %d/%d\n' "${passes}" "${total}"
