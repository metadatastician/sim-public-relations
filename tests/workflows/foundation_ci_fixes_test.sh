#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Unit and regression tests for the foundation CI workflow hardening.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
codeql="${root}/.github/workflows/codeql.yml"
governance="${root}/.github/workflows/governance.yml"
hypatia="${root}/.github/workflows/hypatia-scan.yml"
scorecard="${root}/.github/workflows/scorecard.yml"

passes=0
total=0

pass() {
  passes=$((passes + 1))
  printf 'ok %d - %s\n' "${total}" "$1"
}

fail() {
  printf 'not ok %d - %s\n%s\n' "${total}" "$1" "$2" >&2
  exit 1
}

assert_equal() {
  local label="$1" expected="$2" actual="$3"
  total=$((total + 1))
  if [[ "${actual}" != "${expected}" ]]; then
    fail "${label}" "expected '${expected}', got '${actual}'"
  fi
  pass "${label}"
}

assert_contains() {
  local label="$1" text="$2" value="$3"
  total=$((total + 1))
  if [[ "${value}" != *"${text}"* ]]; then
    fail "${label}" "missing: ${text}"
  fi
  pass "${label}"
}

assert_absent() {
  local label="$1" text="$2" file="$3"
  total=$((total + 1))
  if grep -Fq -- "${text}" "${file}"; then
    fail "${label}" "unexpectedly found '${text}' in ${file}"
  fi
  pass "${label}"
}

assert_full_sha() {
  local label="$1" ref="$2"
  total=$((total + 1))
  if [[ ! "${ref}" =~ ^[0-9a-f]{40}$ ]]; then
    fail "${label}" "expected a lowercase 40-character commit SHA, got: ${ref}"
  fi
  pass "${label}"
}

ref_for() {
  local file="$1" action="$2"
  awk -v action="${action}" '
    {
      line = $0
      sub(/^[[:space:]]*uses:[[:space:]]*/, "", line)
      prefix = action "@"
      if (index(line, prefix) == 1) {
        line = substr(line, length(prefix) + 1)
        sub(/[[:space:]#].*$/, "", line)
        print line
      }
    }
  ' "${file}"
}

checkout_ref="$(ref_for "${codeql}" 'actions/checkout')"
assert_equal 'CodeQL checkout uses the reviewed v7.0.1 commit' \
  '3d3c42e5aac5ba805825da76410c181273ba90b1' "${checkout_ref}"
assert_full_sha 'CodeQL checkout is immutable' "${checkout_ref}"

checkout_step="$(awk '
  /^[[:space:]]*- name:/ {
    if (found) exit
    in_step = 0
  }
  /^[[:space:]]+uses: actions\/checkout@/ {
    found = 1
    in_step = 1
  }
  in_step { print }
' "${codeql}")"
assert_contains 'CodeQL checkout disables persisted credentials' \
  'persist-credentials: false' "${checkout_step}"
assert_absent 'CodeQL checkout never enables persisted credentials' \
  'persist-credentials: true' "${codeql}"

init_ref="$(ref_for "${codeql}" 'github/codeql-action/init')"
analyze_ref="$(ref_for "${codeql}" 'github/codeql-action/analyze')"
assert_equal 'CodeQL init uses the reviewed commit' \
  'cdf488f595d80d6e07e03d4674febd5ab45fa938' "${init_ref}"
assert_equal 'CodeQL analyze uses the reviewed commit' \
  'cdf488f595d80d6e07e03d4674febd5ab45fa938' "${analyze_ref}"
assert_full_sha 'CodeQL init is immutable' "${init_ref}"
assert_full_sha 'CodeQL analyze is immutable' "${analyze_ref}"
assert_equal 'CodeQL init and analyze cannot drift independently' \
  "${init_ref}" "${analyze_ref}"
assert_absent 'CodeQL checkout does not regress to a floating version tag' \
  'uses: actions/checkout@v' "${codeql}"
assert_absent 'CodeQL actions do not regress to floating version tags' \
  'uses: github/codeql-action/init@v' "${codeql}"
assert_absent 'CodeQL analysis does not regress to a floating version tag' \
  'uses: github/codeql-action/analyze@v' "${codeql}"

governance_ref="$(ref_for "${governance}" 'hyperpolymath/standards/.github/workflows/governance-reusable.yml')"
hypatia_ref="$(ref_for "${hypatia}" 'hyperpolymath/standards/.github/workflows/hypatia-scan-reusable.yml')"
scorecard_ref="$(ref_for "${scorecard}" 'hyperpolymath/standards/.github/workflows/scorecard-reusable.yml')"

assert_equal 'governance uses its current standards revision' \
  '8f31a5a4ba591d544b65f91f6d78b136e07756f0' "${governance_ref}"
assert_equal 'Hypatia uses its current standards revision' \
  'cc58c0cb23f73fc2019ce85a56a468e5248a93b3' "${hypatia_ref}"
assert_equal 'Scorecard uses its current standards revision' \
  '8750b94ac1bbe8c51ad13fe106669b13478f0b62' "${scorecard_ref}"
assert_full_sha 'governance reusable workflow is immutable' "${governance_ref}"
assert_full_sha 'Hypatia reusable workflow is immutable' "${hypatia_ref}"
assert_full_sha 'Scorecard reusable workflow is immutable' "${scorecard_ref}"

for workflow in "${governance}" "${hypatia}" "${scorecard}"; do
  assert_absent "$(basename "${workflow}") drops the superseded standards revision" \
    'bd0df9ead7faf0cdfe0e13e7966d91e28d0101d4' "${workflow}"
done

printf 'PASS foundation CI hardening tests: %d/%d\n' "${passes}" "${total}"
