#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Proves the scenario validator both passes clean content and rejects seeded
# boundary failures. A negative scan is not trusted until a positive is planted.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="${root}/tools/validate-scenario.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT
passes=0
total=4

stage() {
  local destination="$1"
  mkdir -p "${destination}"
  cp -R "${root}/scenarios" "${root}/rule-packs" "${root}/tools" \
    "${root}/src" "${destination}/"
  cp "${root}/build.zig" "${destination}/"
}

expect_pass() {
  local candidate="$1" label="$2"
  if "${validator}" "${candidate}" >/dev/null 2>&1; then
    passes=$((passes + 1))
    printf 'canary ok (clean pass): %s\n' "${label}"
  else
    printf 'CANARY FAILED: clean candidate rejected: %s\n' "${label}" >&2
    exit 1
  fi
}

expect_fail() {
  local candidate="$1" label="$2"
  if "${validator}" "${candidate}" >/dev/null 2>&1; then
    printf 'CANARY FAILED: seeded defect passed: %s\n' "${label}" >&2
    exit 1
  else
    passes=$((passes + 1))
    printf 'canary ok (defect caught): %s\n' "${label}"
  fi
}

stage "${scratch}/clean"
expect_pass "${scratch}/clean" "untouched scenario"

stage "${scratch}/leak"
printf '\nbellweather-partner-approval-is-withheld\n' >> \
  "${scratch}/leak/scenarios/northstar-mobility-001/manifest/public.a2ml"
expect_fail "${scratch}/leak" "hidden truth in public manifest"

stage "${scratch}/vacuous"
printf '%s\n' '[reality]' 'delivery = "never-to-learner-client"' \
  '[fixed-history]' 'state = "plain"' > \
  "${scratch}/vacuous/scenarios/northstar-mobility-001/reality/reality.a2ml"
expect_fail "${scratch}/vacuous" "empty hidden-truth denylist"

stage "${scratch}/claim"
sed -i 's/employment-experience = false/employment-experience = true/' \
  "${scratch}/claim/scenarios/northstar-mobility-001/manifest/scenario.a2ml"
expect_fail "${scratch}/claim" "simulation represented as employment experience"

printf 'PASS scenario boundary canaries: %s/%s\n' "${passes}" "${total}"
