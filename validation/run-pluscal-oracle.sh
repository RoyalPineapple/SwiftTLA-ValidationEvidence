#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
case_id= checkout= commit= requested_ref= mode=candidate validation_commit= output=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --case) case_id="$2"; shift 2 ;; --checkout) checkout="$2"; shift 2 ;;
    --commit) commit="$2"; shift 2 ;; --requested-ref) requested_ref="$2"; shift 2 ;;
    --mode) mode="$2"; shift 2 ;; --validation-commit) validation_commit="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;; *) exit 2 ;;
  esac
done
fail() { mkdir -p "$output"; jq -n --arg whatFailed "$1" --arg whereItFailed "$2" --arg expected "$3" --arg actual "$4" --arg systemChange "$5" --arg nextSafeAction "$6" '{whatFailed:$whatFailed,whereItFailed:$whereItFailed,expected:$expected,actual:$actual,systemChange:$systemChange,nextSafeAction:$nextSafeAction}' > "$output/diagnostic.json"; exit 2; }
[ -n "$case_id" ] && [ -n "$checkout" ] && [ -n "$commit" ] && [ -n "$requested_ref" ] && [ -n "$validation_commit" ] && [ -n "$output" ] || exit 2
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || fail "Invalid candidate SHA" "runner arguments" "40-character SHA" "$commit" "No run started" "Use the resolved checkout SHA."
[ "$(git -C "$checkout" rev-parse HEAD)" = "$commit" ] || fail "Candidate checkout mismatch" "$checkout" "$commit" "unresolved" "No run started" "Check out exactly the candidate SHA."
[ ! -e "$output" ] || fail "Evidence directory exists" "$output" "fresh directory" "already exists" "No run started" "Choose a fresh output directory."
mkdir -p "$output"

contract="$root/validation/pluscal-oracle.json"
required_ids="$(jq -r '.requiredCases[].fixtureID' "$contract")"
suite_ids="$(jq -r '.suite.requiresFixtureIDs[]' "$contract")"
if ! diff -u <(printf '%s\n' "$required_ids" | sed '/^$/d' | sort) <(printf '%s\n' "$suite_ids" | sed '/^$/d' | sort) >/dev/null; then
  fail "Differential suite contract differs from required fixtures" "$contract" "the suite to require exactly the named fixture contract" "required and suite fixture lists differ" "No run started" "Repair the stable admission contract."
fi
if [ "$(printf '%s\n' "$required_ids" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')" -ne 6 ]; then
  fail "Invalid required fixture contract" "$contract" "six unique fixture IDs" "duplicate or missing fixture IDs" "No run started" "Repair the stable admission contract."
fi
case "$mode" in candidate|admission) ;; *) fail "Invalid evidence mode" "runner arguments" "candidate or admission" "$mode" "No run started" "Use a supported evidence mode." ;; esac
if [ "$mode" = admission ] && [ "$requested_ref" != main ]; then
  fail "Admission was not requested from main" "workflow input swifttla_ref" "main" "$requested_ref" "Candidate checkout retained; no admission claim" "Merge the candidate, then admit the immutable main revision."
fi
if [ "$mode" = admission ] && [ "$case_id" != all ]; then
  fail "Admission did not select the complete fixture contract" "runner argument --case" "all required fixtures" "$case_id" "No fixture run started; no admission claim" "Run admission with --case all."
fi

if [ "$case_id" = all ]; then
  suite="$output/pluscal-differential-audit"
  if ! ids="$(swift run --package-path "$root/validation/pluscal-oracle-harness" pluscal-oracle-harness --list)"; then
    mkdir "$suite"
    jq -n --arg commit "$commit" --arg requestedRef "$requested_ref" --arg validationCommit "$validation_commit" --arg mode "$mode" '{schema:"SwiftTLAPlusCalDifferentialAuditV1",id:"pluscal-differential-audit",requestedRef:$requestedRef,resolvedCommit:$commit,validationCommit:$validationCommit,mode:$mode,fixtureResults:[],conformant:false}' > "$suite/result.json"
    jq -n '{whatFailed:"PlusCal differential audit",whereItFailed:"pluscal-oracle-harness --list",expected:"the registered Algorithm fixture list",actual:"the fixture-export harness did not list fixtures",systemChange:"No fixture or TLC run started; no admission claim was made.",nextSafeAction:"Repair the fixture-export harness, then dispatch one fresh hosted candidate run."}' > "$suite/diagnostic.json"
    exit 2
  fi
  printf '{"requestedRef":"%s","resolvedCommit":"%s","validationCommit":"%s","mode":"%s"}\n' "$requested_ref" "$commit" "$validation_commit" "$mode" > "$output/run.json"
  status=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    "$0" --case "$id" --checkout "$checkout" --commit "$commit" --requested-ref "$requested_ref" --mode "$mode" --validation-commit "$validation_commit" --output "$output/$id" || status=$?
  done <<< "$ids"
  mkdir "$suite"
  fixture_results="$({ while IFS= read -r id; do
    [ -n "$id" ] || continue
    if [ -f "$output/$id/comparison.json" ] && jq -e '.conformant == true' "$output/$id/comparison.json" >/dev/null; then
      jq -cn --arg id "$id" '{fixtureID:$id,status:"conformant",evidence:"comparison.json"}'
    elif [ -f "$output/$id/diagnostic.json" ]; then
      jq -cn --arg id "$id" '{fixtureID:$id,status:"failed",evidence:"diagnostic.json"}'
    else
      jq -cn --arg id "$id" '{fixtureID:$id,status:"missing",evidence:null}'
    fi
  done <<< "$ids"; } | jq -s .)"
  discovered_ids="$(printf '%s\n' "$ids" | sed '/^$/d' | sort)"
  expected_ids="$(printf '%s\n' "$required_ids" | sed '/^$/d' | sort)"
  missing="$(comm -23 <(printf '%s\n' "$expected_ids") <(printf '%s\n' "$discovered_ids"))"
  unexpected="$(comm -13 <(printf '%s\n' "$expected_ids") <(printf '%s\n' "$discovered_ids"))"
  failed="$(jq '[.[] | select(.status != "conformant")] | length' <<< "$fixture_results")"
  jq -n --arg commit "$commit" --arg requestedRef "$requested_ref" --arg validationCommit "$validation_commit" --arg mode "$mode" --argjson fixtures "$fixture_results" --argjson failed "$failed" --arg missing "$missing" --arg unexpected "$unexpected" '{schema:"SwiftTLAPlusCalDifferentialAuditV2",id:"pluscal-differential-audit",requestedRef:$requestedRef,resolvedCommit:$commit,validationCommit:$validationCommit,mode:$mode,fixtureResults:$fixtures,missingFixtureIDs:($missing | split("\n") | map(select(length > 0))),unexpectedFixtureIDs:($unexpected | split("\n") | map(select(length > 0))),conformant:($failed == 0 and $missing == "" and $unexpected == "")}' > "$suite/result.json"
  if [ "$failed" -ne 0 ] || [ -n "$missing" ] || [ -n "$unexpected" ]; then
    jq -n --arg actual "failed fixture results: $failed; missing IDs: ${missing:-none}; unexpected IDs: ${unexpected:-none}; inspect pluscal-differential-audit/result.json and retained fixture evidence" '{whatFailed:"PlusCal differential audit",whereItFailed:"pluscal-differential-audit/result.json",expected:"every required fixture to have an exact Swift-lowered versus official-PlusCal/TLC graph comparison",actual:$actual,systemChange:"Per-fixture evidence was retained; no admission claim was made.",nextSafeAction:"Repair the named fixture or lowerer, then dispatch one fresh hosted candidate run."}' > "$suite/diagnostic.json"
    [ "$status" -ne 0 ] || status=1
  fi
  exit "$status"
fi

swift run --package-path "$root/validation/pluscal-oracle-harness" pluscal-oracle-harness "$case_id" "$output/input" "$commit" || fail "Fixture export failed" "$case_id" "renderable registered fixture" "harness failed" "No TLC run" "Repair the fixture boundary."
jq -n --arg id "$case_id" --arg ref "$requested_ref" --arg commit "$commit" --arg validationCommit "$validation_commit" --arg module "$(shasum -a 256 "$output/input/swift-lowered.tla" | awk '{print $1}')" --arg config "$(shasum -a 256 "$output/input/model.cfg" | awk '{print $1}')" --arg pluscal "$(shasum -a 256 "$output/input/pluscal-source.tla" | awk '{print $1}')" '{id:$id,requestedRef:$ref,resolvedCommit:$commit,validationCommit:$validationCommit,moduleSHA256:$module,cfgSHA256:$config,plusCalSourceSHA256:$pluscal}' > "$output/case.json"
jq -n --arg id "$case_id" --arg commit "$commit" '{runner:{caseID:$id,engine:"pluscal-oracle",runID:$commit},swift:{caseID:$id,engine:"swift",runID:$commit},tlc:{caseID:$id,engine:"tlc",runID:$commit}}' > "$output/correlations.json"
printf '{"swiftLowered":true,"pluscalSource":true,"translatorOutput":false,"swiftTLC":false,"pluscalTLC":false}\n' > "$output/raw-artifacts.json"
mkdir "$output/translated" "$output/swift-tlc" "$output/pluscal-tlc"
jar="$root/.build/tla2tools.jar"; mkdir -p "$root/.build"
if [ ! -f "$jar" ]; then curl -fsSL https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar -o "$jar"; fi
jar_digest="$(shasum -a 256 "$jar" | awk '{print $1}')"
[ "$jar_digest" = "ab323b79802aedc3203b3f9af37c6aca3ed43f4e0225b36f2aa77b26de46c05f" ] || fail "Pinned TLC jar digest differs" "$jar" "TLC v1.8.0 pinned digest" "untrusted jar" "No translator or TLC run" "Restore the pinned TLC artifact."
jq -n --arg jarSHA256 "$jar_digest" --arg javaVersion "$(java -version 2>&1 | head -1)" '{tla2tools:{version:"1.8.0",artifact:"tla2tools.jar",sha256:$jarSHA256},javaVersion:$javaVersion,translator:"pcal.trans",modelChecker:"tlc2.TLC"}' > "$output/toolchain.json"
module_name() { awk '/^---- MODULE [[:alnum:]_]+ ----$/ { print $3; exit }' "$1"; }
prepare_module() { local source="$1" destination="$2" name; name="$(module_name "$source")"; [ -n "$name" ] || fail "Missing TLA+ module name" "$source" "top-level MODULE declaration" "no valid module header" "Inputs retained" "Render a named module."; cp "$source" "$destination/$name.tla"; printf '%s\n' "$name"; }
pluscal_module="$(prepare_module "$output/input/pluscal-source.tla" "$output/translated")"
cp "$output/input/model.cfg" "$output/translated/model.cfg"
jq -n --arg swiftExport "swift run --package-path $root/validation/pluscal-oracle-harness pluscal-oracle-harness $case_id $output/input $commit" --arg pluscal "java -cp $jar pcal.trans -unixEOL $output/translated/$pluscal_module.tla" --arg tlc "java -cp $jar tlc2.TLC -workers 1 -fp 1 -deadlock -metadir <kind>/states -dump dot,actionlabels <kind>/graph.dot -config <kind>/model.cfg <kind>/<module>.tla" '{fixtureExport:$swiftExport,pluscalTranslator:$pluscal,tlc:$tlc}' > "$output/commands.json"
java -cp "$jar" pcal.trans -unixEOL "$output/translated/$pluscal_module.tla" > "$output/translation.stdout" 2> "$output/translation.stderr" || fail "PlusCal translation failed" "$case_id" "pcal.trans success" "See translation.stderr" "Inputs retained" "Inspect the rendered source."
for kind in swift pluscal; do
  if [ "$kind" = swift ]; then module_name="$(prepare_module "$output/input/swift-lowered.tla" "$output/$kind-tlc")"; else module_name="$pluscal_module"; cp "$output/translated/$module_name.tla" "$output/$kind-tlc/$module_name.tla"; fi
  cp "$output/input/model.cfg" "$output/$kind-tlc/model.cfg"
  module="$output/$kind-tlc/$module_name.tla"; config="$output/$kind-tlc/model.cfg"
  java -cp "$jar" tlc2.TLC -workers 1 -fp 1 -deadlock -metadir "$output/$kind-tlc/states" -dump dot,actionlabels "$output/$kind-tlc/graph.dot" -config "$config" "$module" > "$output/$kind-tlc/tlc.stdout" 2> "$output/$kind-tlc/tlc.stderr" || fail "TLC run failed" "$kind" "complete bounded TLC graph" "See retained TLC stdout and stderr" "Inputs retained" "Inspect retained TLC output."
  "$root/validation/canonicalize-tlc-dot.rb" "$output/$kind-tlc/graph.dot" "$output/$kind-tlc/canonical-graph.json"
done
cmp -s "$output/swift-tlc/canonical-graph.json" "$output/pluscal-tlc/canonical-graph.json" || fail "TLC graphs differ" "$case_id" "exact canonical graphs" "Graphs differ" "No admission claim" "Inspect retained graphs."
jq -n --arg id "$case_id" --arg commit "$commit" --arg swiftGraph "$(shasum -a 256 "$output/swift-tlc/graph.dot" | awk '{print $1}')" --arg pluscalGraph "$(shasum -a 256 "$output/pluscal-tlc/graph.dot" | awk '{print $1}')" --arg swiftCanonical "$(shasum -a 256 "$output/swift-tlc/canonical-graph.json" | awk '{print $1}')" --arg pluscalCanonical "$(shasum -a 256 "$output/pluscal-tlc/canonical-graph.json" | awk '{print $1}')" '{id:$id,resolvedCommit:$commit,conformant:true,differences:[],rawGraphSHA256:{swift:$swiftGraph,pluscal:$pluscalGraph},canonicalGraphSHA256:{swift:$swiftCanonical,pluscal:$pluscalCanonical}}' > "$output/comparison.json"
jq -n --arg translatedModule "$(shasum -a 256 "$output/translated/$pluscal_module.tla" | awk '{print $1}')" --arg translationStdout "$(shasum -a 256 "$output/translation.stdout" | awk '{print $1}')" --arg translationStderr "$(shasum -a 256 "$output/translation.stderr" | awk '{print $1}')" --arg swiftStdout "$(shasum -a 256 "$output/swift-tlc/tlc.stdout" | awk '{print $1}')" --arg swiftStderr "$(shasum -a 256 "$output/swift-tlc/tlc.stderr" | awk '{print $1}')" --arg pluscalStdout "$(shasum -a 256 "$output/pluscal-tlc/tlc.stdout" | awk '{print $1}')" --arg pluscalStderr "$(shasum -a 256 "$output/pluscal-tlc/tlc.stderr" | awk '{print $1}')" '{translatedModuleSHA256:$translatedModule,translatorOutputSHA256:{stdout:$translationStdout,stderr:$translationStderr},tlcOutputSHA256:{swift:{stdout:$swiftStdout,stderr:$swiftStderr},pluscal:{stdout:$pluscalStdout,stderr:$pluscalStderr}}}' > "$output/output-digests.json"
printf '{"swiftLowered":true,"pluscalSource":true,"translatorOutput":true,"swiftTLC":true,"pluscalTLC":true}\n' > "$output/raw-artifacts.json"
