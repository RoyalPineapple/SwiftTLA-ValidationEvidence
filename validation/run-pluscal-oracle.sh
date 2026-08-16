#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
case_id= checkout= commit= requested_ref= mode=candidate output=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --case) case_id="$2"; shift 2 ;; --checkout) checkout="$2"; shift 2 ;;
    --commit) commit="$2"; shift 2 ;; --requested-ref) requested_ref="$2"; shift 2 ;;
    --mode) mode="$2"; shift 2 ;; --output) output="$2"; shift 2 ;;
    *) exit 2 ;;
  esac
done
fail() { mkdir -p "$output"; jq -n --arg whatFailed "$1" --arg whereItFailed "$2" --arg expected "$3" --arg actual "$4" --arg systemChange "$5" --arg nextSafeAction "$6" '{whatFailed:$whatFailed,whereItFailed:$whereItFailed,expected:$expected,actual:$actual,systemChange:$systemChange,nextSafeAction:$nextSafeAction}' > "$output/diagnostic.json"; exit 2; }
[ -n "$case_id" ] && [ -n "$checkout" ] && [ -n "$commit" ] && [ -n "$requested_ref" ] && [ -n "$output" ] || exit 2
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || fail "Invalid candidate SHA" "runner arguments" "40-character SHA" "$commit" "No run started" "Use the resolved checkout SHA."
[ "$(git -C "$checkout" rev-parse HEAD)" = "$commit" ] || fail "Candidate checkout mismatch" "$checkout" "$commit" "unresolved" "No run started" "Check out exactly the candidate SHA."
[ ! -e "$output" ] || fail "Evidence directory exists" "$output" "fresh directory" "already exists" "No run started" "Choose a fresh output directory."
mkdir -p "$output"
mapped="$(jq -r --arg commit "$commit" '[.admissionCases[] | select(.commit == $commit and .fixtureID != null)] | length' "$root/validation/pluscal-oracle.json")"
if [ "$mode" = admission ] && [ "$mapped" -ne 6 ]; then
  fail "External K1-K6 admission is not configured" "validation/pluscal-oracle.json" "six exact mappings" "$mapped mappings" "Candidate checkout retained; no admission claim" "Add six reviewed mappings for this SHA."
fi
if [ "$case_id" = all ]; then
  ids="$(swift run --package-path "$root/validation/pluscal-oracle-harness" pluscal-oracle-harness --list)"
  printf '{"requestedRef":"%s","resolvedCommit":"%s","mode":"%s"}\n' "$requested_ref" "$commit" "$mode" > "$output/run.json"
  status=0; while IFS= read -r id; do [ -n "$id" ] || continue; "$0" --case "$id" --checkout "$checkout" --commit "$commit" --requested-ref "$requested_ref" --mode "$mode" --output "$output/$id" || status=$?; done <<< "$ids"
  exit "$status"
fi
swift run --package-path "$root/validation/pluscal-oracle-harness" pluscal-oracle-harness "$case_id" "$output/input" "$commit" || fail "Fixture export failed" "$case_id" "renderable registered fixture" "harness failed" "No TLC run" "Repair the fixture boundary."
jq -n --arg id "$case_id" --arg ref "$requested_ref" --arg commit "$commit" \
  --arg module "$(shasum -a 256 "$output/input/swift-lowered.tla" | awk '{print $1}')" \
  --arg config "$(shasum -a 256 "$output/input/model.cfg" | awk '{print $1}')" \
  --arg pluscal "$(shasum -a 256 "$output/input/pluscal-source.tla" | awk '{print $1}')" \
  '{id:$id,requestedRef:$ref,resolvedCommit:$commit,moduleSHA256:$module,cfgSHA256:$config,plusCalSourceSHA256:$pluscal}' > "$output/case.json"
jq -n --arg id "$case_id" --arg commit "$commit" '{runner:{caseID:$id,engine:"pluscal-oracle",runID:$commit},swift:{caseID:$id,engine:"swift",runID:$commit},tlc:{caseID:$id,engine:"tlc",runID:$commit}}' > "$output/correlations.json"
printf '{"swiftLowered":true,"pluscalSource":true,"translatorOutput":false,"swiftTLC":false,"pluscalTLC":false}\n' > "$output/raw-artifacts.json"
mkdir "$output/translated" "$output/swift-tlc" "$output/pluscal-tlc"
jar="$root/.build/tla2tools.jar"; mkdir -p "$root/.build"
if [ ! -f "$jar" ]; then curl -fsSL https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar -o "$jar"; fi
cp "$output/input/pluscal-source.tla" "$output/translated/pluscal-source.tla"; cp "$output/input/model.cfg" "$output/translated/model.cfg"
java -cp "$jar" pcal.trans -unixEOL "$output/translated/pluscal-source.tla" > "$output/translation.stdout" 2> "$output/translation.stderr" || fail "PlusCal translation failed" "$case_id" "pcal.trans success" "See translation.stderr" "Inputs retained" "Inspect the rendered source."
for kind in swift pluscal; do
  if [ "$kind" = swift ]; then module="$output/input/swift-lowered.tla"; config="$output/input/model.cfg"; else module="$output/translated/pluscal-source.tla"; config="$output/translated/model.cfg"; fi
  java -cp "$jar" tlc2.TLC -workers 1 -fp 1 -deadlock -metadir "$output/$kind-tlc/states" -dump dot,actionlabels "$output/$kind-tlc/graph.dot" -config "$config" "$module" > "$output/$kind-tlc/tlc-output.txt" 2>&1 || fail "TLC run failed" "$kind" "complete bounded TLC graph" "See TLC output" "Inputs retained" "Inspect TLC output."
  "$root/validation/canonicalize-tlc-dot.rb" "$output/$kind-tlc/graph.dot" "$output/$kind-tlc/canonical-graph.json"
done
cmp -s "$output/swift-tlc/canonical-graph.json" "$output/pluscal-tlc/canonical-graph.json" || fail "TLC graphs differ" "$case_id" "exact canonical graphs" "Graphs differ" "No admission claim" "Inspect retained graphs."
jq -n --arg id "$case_id" --arg commit "$commit" '{id:$id,resolvedCommit:$commit,conformant:true,differences:[]}' > "$output/comparison.json"
printf '{"swiftLowered":true,"pluscalSource":true,"translatorOutput":true,"swiftTLC":true,"pluscalTLC":true}\n' > "$output/raw-artifacts.json"
