#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
scenario="${root}/scenarios/northstar-mobility-001"

fail() {
  printf 'FAIL scenario: %s\n' "$1" >&2
  exit 1
}

required=(
  "${scenario}/manifest/scenario.a2ml"
  "${scenario}/manifest/public.a2ml"
  "${scenario}/reality/reality.a2ml"
  "${scenario}/actors/actors.a2ml"
  "${scenario}/evidence/requestable-evidence.a2ml"
  "${scenario}/evidence/client-email.adoc"
  "${scenario}/evidence/rough-brief.adoc"
  "${scenario}/evidence/product-fact-sheet.adoc"
  "${scenario}/tasks/workstreams.a2ml"
  "${scenario}/tasks/routes.a2ml"
  "${scenario}/assessment/rubric-map.a2ml"
  "${scenario}/fixtures/golden-runs.a2ml"
  "${root}/rule-packs/uk-pr-practice-provisional/pack.a2ml"
  "${root}/build.zig"
  "${root}/src/practice.zig"
  "${root}/src/main.zig"
)

for file in "${required[@]}"; do
  [[ -s "${file}" ]] || fail "missing or empty ${file#"${root}/"}"
done

grep -q '^id = "northstar-mobility-001"$' "${scenario}/manifest/scenario.a2ml" ||
  fail "scenario manifest has the wrong identity"
grep -q '^id = "northstar-mobility-001"$' "${scenario}/manifest/public.a2ml" ||
  fail "public manifest has the wrong identity"
grep -q '^delivery = "never-to-learner-client"$' "${scenario}/reality/reality.a2ml" ||
  fail "reality does not declare the learner delivery boundary"
grep -q '^one-correct-path = false$' "${scenario}/assessment/rubric-map.a2ml" ||
  fail "rubric permits a hidden one-correct-path design"
grep -q '^outcome-equals-competence = false$' "${scenario}/assessment/rubric-map.a2ml" ||
  fail "rubric conflates campaign outcome with competence"
grep -q '^one-correct-route = false$' "${scenario}/tasks/routes.a2ml" ||
  fail "route model permits only one correct route"
grep -q '^employment-experience = false$' "${scenario}/manifest/scenario.a2ml" ||
  fail "scenario does not reject the employment-experience claim"
grep -q '^authoritative-scoring = false$' "${root}/rule-packs/uk-pr-practice-provisional/pack.a2ml" ||
  fail "unreviewed rule pack claims authoritative scoring"
grep -q 'pub const scenario_id = "northstar-mobility-001";' "${root}/src/practice.zig" ||
  fail "native kernel scenario identity drifted from the manifest"
grep -q 'pub const rule_pack = "uk-pr-practice-provisional@0.1.0";' "${root}/src/practice.zig" ||
  fail "native kernel rule-pack identity drifted from the manifest"

for run in \
  corrected-launch-standard staged-launch-standard \
  pause-and-replan-alternative narrow-owned-launch-alternative \
  threshold-with-supported-escalation output-volume-no-outcome \
  late-approval blanket-pitch invented-endorsement knowingly-false-claim \
  contact-data-to-ai
do
  grep -q "\"${run}\"" "${scenario}/fixtures/golden-runs.a2ml" ||
    fail "missing golden-run declaration ${run}"
done

# Derive exact, scenario-specific deny phrases from trusted reality. This must
# produce a non-empty set, otherwise a leak scan could pass vacuously.
denylist="$(mktemp)"
trap 'rm -f "${denylist}"' EXIT
awk '
  /^\[fixed-history\]$/ { inside = 1; next }
  /^\[/ { inside = 0 }
  inside && match($0, /"[^"]+"/) {
    value = substr($0, RSTART + 1, RLENGTH - 2)
    if (value ~ /-/) print value
  }
' "${scenario}/reality/reality.a2ml" | sort -u > "${denylist}"

[[ -s "${denylist}" ]] || fail "hidden-truth denylist is empty"

learner_sources=(
  "${scenario}/manifest/public.a2ml"
  "${scenario}/actors"
  "${scenario}/tasks"
  "${scenario}/evidence/client-email.adoc"
  "${scenario}/evidence/rough-brief.adoc"
  "${scenario}/evidence/product-fact-sheet.adoc"
  "${root}/src"
)

if grep -R -n -F -f "${denylist}" "${learner_sources[@]}"; then
  fail "trusted reality leaked into learner-visible source"
fi

if find "${scenario}" -path '*/learner/*' -type d -name reality -print -quit |
  grep -q .; then
  fail "learner structure contains a reality directory"
fi

deny_count="$(wc -l < "${denylist}")"
printf 'PASS scenario: structure, plural routes, claim boundary and %s hidden-truth tokens\n' \
  "${deny_count}"
