#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
case_id= checkout= commit= requested_ref= mode=candidate validation_commit= output=
fixture_export_timeout_seconds=180
fixture_registry_timeout_seconds=600
pluscal_translation_timeout_seconds=30
tlc_timeout_seconds=90
timeout_exit=124
while [ "$#" -gt 0 ]; do
  case "$1" in
    --case) case_id="$2"; shift 2 ;; --checkout) checkout="$2"; shift 2 ;;
    --commit) commit="$2"; shift 2 ;; --requested-ref) requested_ref="$2"; shift 2 ;;
    --mode) mode="$2"; shift 2 ;; --validation-commit) validation_commit="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;; *) exit 2 ;;
  esac
done
fail() { mkdir -p "$output"; jq -n --arg whatFailed "$1" --arg whereItFailed "$2" --arg expected "$3" --arg actual "$4" --arg systemChange "$5" --arg nextSafeAction "$6" '{whatFailed:$whatFailed,whereItFailed:$whereItFailed,expected:$expected,actual:$actual,systemChange:$systemChange,nextSafeAction:$nextSafeAction}' > "$output/diagnostic.json"; exit 2; }
run_bounded() {
  local limit_seconds="$1" stdout="$2" stderr="$3" pid started status timed_out=0
  shift 3
  /usr/bin/perl -MPOSIX=setsid -e 'setsid() or die "setsid: $!"; exec @ARGV or die "exec $ARGV[0]: $!";' -- "$@" > "$stdout" 2> "$stderr" &
  pid=$!
  started=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS - started >= limit_seconds )); then
      timed_out=1
      # The Perl launcher makes this command the leader of its own session and process group.
      # A negative PID therefore terminates the command and every descendant it started.
      kill -TERM -- "-$pid" 2>/dev/null || true
      sleep 5
      kill -KILL -- "-$pid" 2>/dev/null || true
      break
    fi
    sleep 1
  done
  if wait "$pid"; then status=0; else status=$?; fi
  [ "$timed_out" -eq 0 ] || return "$timeout_exit"
  return "$status"
}
timeout_failure() {
  local operation="$1" fixture="$2" limit_seconds="$3" stdout="$4" stderr="$5"
  fail "$operation timed out" "fixture $fixture / $operation" "the bounded fixture to finish within $limit_seconds seconds" "fixture $fixture exceeded the $limit_seconds-second limit; inspect $stdout and $stderr" "The timed-out process group was terminated; partial stdout and stderr were retained; no admission claim was made." "Inspect the retained output, repair the named operation or fixture, then dispatch one fresh hosted candidate run."
}
external_module_bundle_json='null'
stage_voteproof_tlaps_modules() {
  local manifest="$root/validation/external-modules/voteproof-tlaps.json" imports name path expected actual source_url provenance_digest module_hashes
  imports="$output/input/imports"
  [ -f "$manifest" ] || fail "VoteProof external module manifest is missing" "$manifest" "the pinned TLAPS module bundle" "manifest was not found" "No TLC run started" "Restore the manifest-pinned upstream module inputs."
  jq -e '
    .schema == "SwiftTLAExternalModuleBundleV1"
      and .fixtureID == "voteproof-upstream-port"
      and ([.modules[] | .name] | sort == ["FiniteSetTheorems", "Folds", "Functions", "NaturalsInduction", "TLAPS", "WellFoundedInduction"])
      and ([.modules[] | select(
        (.path | test("^(library|modules)/[A-Za-z]+\\.tla$"))
          and (.sha256 | test("^[0-9a-f]{64}$"))
          and (.source.githubRepository | IN("tlaplus/tlapm", "tlaplus/CommunityModules"))
          and (.source.commit | test("^[0-9a-f]{40}$"))
      )] | length == 6)
  ' "$manifest" >/dev/null || fail "VoteProof external module manifest is invalid" "$manifest" "the exact pinned TLAPS dependency closure" "manifest schema, source pin, or module set differs" "No TLC run started" "Repair the manifest with the authoritative TLAPS module closure."
  mkdir -p "$imports"
  cp "$manifest" "$output/input/external-module-provenance.json"
  while IFS=$'\t' read -r name path expected github_repository source_commit; do
    source_url="https://raw.githubusercontent.com/$github_repository/$source_commit/$path"
    if ! curl --fail --location --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 30 --silent --show-error "$source_url" -o "$imports/$name.tla"; then
      fail "VoteProof external module fetch failed" "fixture voteproof-upstream-port / $name" "the pinned TLAPS source at $source_url" "curl could not retrieve the pinned module" "No TLC run started; the manifest and partial inputs were retained." "Restore the pinned upstream source or retry a fresh hosted candidate run."
    fi
    actual="$(shasum -a 256 "$imports/$name.tla" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || fail "VoteProof external module digest differs" "fixture voteproof-upstream-port / $name" "$expected" "$actual" "No TLC run started; the fetched input and provenance were retained." "Update only after reviewing a new authoritative TLAPS pin."
  done < <(jq -r '.modules[] | [.name, .path, .sha256, .source.githubRepository, .source.commit] | @tsv' "$manifest")
  provenance_digest="$(shasum -a 256 "$output/input/external-module-provenance.json" | awk '{print $1}')"
  module_hashes="$({ for module in "$imports"/*.tla; do jq -n --arg name "imports/$(basename "$module")" --arg digest "$(shasum -a 256 "$module" | awk '{print $1}')" '{($name):$digest}'; done; } | jq -s add)"
  jq --arg provenanceDigest "$provenance_digest" --argjson moduleHashes "$module_hashes" '.inputSHA256 += $moduleHashes + {"external-module-provenance.json": $provenanceDigest}' "$output/input/metadata.json" > "$output/input/metadata.next.json"
  mv "$output/input/metadata.next.json" "$output/input/metadata.json"
  external_module_bundle_json="$(jq -c '. + {manifestSHA256: $manifestSHA256}' --arg manifestSHA256 "$provenance_digest" "$manifest")"
}
[ -n "$case_id" ] && [ -n "$checkout" ] && [ -n "$commit" ] && [ -n "$requested_ref" ] && [ -n "$validation_commit" ] && [ -n "$output" ] || exit 2
if [ "$case_id" = kvsnap-upstream-port ] || [ "$case_id" = voteproof-upstream-port ]; then tlc_timeout_seconds=300; fi
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
required_count="$(printf '%s\n' "$required_ids" | sed '/^$/d' | wc -l | tr -d ' ')"
unique_required_count="$(printf '%s\n' "$required_ids" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
if [ "$required_count" -eq 0 ] || [ "$unique_required_count" -ne "$required_count" ]; then
  fail "Invalid required fixture contract" "$contract" "non-empty, unique required fixture IDs" "missing or duplicate fixture IDs" "No run started" "Repair the stable admission contract."
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
  mkdir -p "$suite"
  if run_bounded "$fixture_registry_timeout_seconds" "$suite/fixture-list.stdout" "$suite/fixture-list.stderr" swift run --jobs 1 --package-path "$root/validation/pluscal-oracle-harness" pluscal-oracle-harness --list; then
    ids="$(<"$suite/fixture-list.stdout")"
  else
    status=$?
    jq -n --arg commit "$commit" --arg requestedRef "$requested_ref" --arg validationCommit "$validation_commit" --arg mode "$mode" '{schema:"SwiftTLAPlusCalDifferentialAuditV1",id:"pluscal-differential-audit",requestedRef:$requestedRef,resolvedCommit:$commit,validationCommit:$validationCommit,mode:$mode,fixtureResults:[],conformant:false}' > "$suite/result.json"
    if [ "$status" -eq "$timeout_exit" ]; then
      jq -n --arg stdout "$suite/fixture-list.stdout" --arg stderr "$suite/fixture-list.stderr" --argjson limit "$fixture_registry_timeout_seconds" '{whatFailed:"Fixture registry export timed out",whereItFailed:"fixture registry / fixture export",expected:("the registered bounded fixtures within " + ($limit | tostring) + " seconds"),actual:("fixture registry export exceeded the limit; inspect " + $stdout + " and " + $stderr),systemChange:"The timed-out process group was terminated; partial stdout and stderr were retained; no admission claim was made.",nextSafeAction:"Inspect retained output, repair the fixture-export harness, then dispatch one fresh hosted candidate run."}' > "$suite/diagnostic.json"
    else
      jq -n --argjson status "$status" --arg stdout "$suite/fixture-list.stdout" --arg stderr "$suite/fixture-list.stderr" '{whatFailed:"Fixture registry export failed",whereItFailed:"fixture registry / fixture export",expected:"the registered Algorithm fixture list",actual:("the fixture-export harness exited " + ($status | tostring) + "; inspect " + $stdout + " and " + $stderr),systemChange:"Fixture export output was retained; no fixture or TLC run started; no admission claim was made.",nextSafeAction:"Repair the fixture-export harness, then dispatch one fresh hosted candidate run."}' > "$suite/diagnostic.json"
    fi
    exit 2
  fi
  printf '{"requestedRef":"%s","resolvedCommit":"%s","validationCommit":"%s","mode":"%s"}\n' "$requested_ref" "$commit" "$validation_commit" "$mode" > "$output/run.json"
  status=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    "$0" --case "$id" --checkout "$checkout" --commit "$commit" --requested-ref "$requested_ref" --mode candidate --validation-commit "$validation_commit" --output "$output/$id" || status=$?
  done <<< "$ids"
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

if run_bounded "$fixture_export_timeout_seconds" "$output/fixture-export.stdout" "$output/fixture-export.stderr" swift run --jobs 1 --package-path "$root/validation/pluscal-oracle-harness" pluscal-oracle-harness "$case_id" "$output/input" "$commit"; then
  :
else
  status=$?
  if [ "$status" -eq "$timeout_exit" ]; then
    timeout_failure "Fixture export" "$case_id" "$fixture_export_timeout_seconds" "$output/fixture-export.stdout" "$output/fixture-export.stderr"
  fi
  fail "Fixture export failed" "fixture $case_id / fixture export" "a renderable registered fixture" "fixture export exited $status; inspect $output/fixture-export.stdout and $output/fixture-export.stderr" "Fixture export output was retained; no TLC run started; no admission claim was made." "Repair the fixture boundary, then dispatch one fresh hosted candidate run."
fi
if [ "$case_id" = voteproof-upstream-port ]; then stage_voteproof_tlaps_modules; fi
jq -n --arg id "$case_id" --arg ref "$requested_ref" --arg commit "$commit" --arg validationCommit "$validation_commit" --arg module "$(shasum -a 256 "$output/input/swift-lowered.tla" | awk '{print $1}')" --arg swiftConfig "$(shasum -a 256 "$output/input/swift.cfg" | awk '{print $1}')" --arg plusCalConfig "$(shasum -a 256 "$output/input/pluscal.cfg" | awk '{print $1}')" --arg pluscal "$(shasum -a 256 "$output/input/pluscal-source.tla" | awk '{print $1}')" --argjson externalModuleBundle "$external_module_bundle_json" '{id:$id,requestedRef:$ref,resolvedCommit:$commit,validationCommit:$validationCommit,moduleSHA256:$module,configurationSHA256:{swift:$swiftConfig,pluscal:$plusCalConfig},plusCalSourceSHA256:$pluscal,externalModuleBundle:$externalModuleBundle}' > "$output/case.json"
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
copy_imports() { local source="$1/imports" destination="$2"; [ -d "$source" ] || return 0; find "$source" -maxdepth 1 -type f -name '*.tla' -exec cp {} "$destination" \;; }
pluscal_module="$(prepare_module "$output/input/pluscal-source.tla" "$output/translated")"
copy_imports "$output/input" "$output/translated"
cp "$output/input/pluscal.cfg" "$output/translated/pluscal.cfg"
jq -n --arg swiftExport "swift run --package-path $root/validation/pluscal-oracle-harness pluscal-oracle-harness $case_id $output/input $commit" --arg pluscal "java -cp $jar pcal.trans -unixEOL $output/translated/$pluscal_module.tla" --arg swiftTLC "java -cp $jar tlc2.TLC -workers 1 -fp 1 -deadlock -metadir swift/states -dump dot,actionlabels swift/graph.dot -config swift/swift.cfg swift/<module>.tla" --arg pluscalTLC "java -cp $jar tlc2.TLC -workers 1 -fp 1 -deadlock -metadir pluscal/states -dump dot,actionlabels pluscal/graph.dot -config pluscal/pluscal.cfg pluscal/<module>.tla" --argjson externalModuleBundle "$external_module_bundle_json" --argjson fixtureExportTimeoutSeconds "$fixture_export_timeout_seconds" --argjson pluscalTranslationTimeoutSeconds "$pluscal_translation_timeout_seconds" --argjson tlcTimeoutSeconds "$tlc_timeout_seconds" '{fixtureExport:$swiftExport,pluscalTranslator:$pluscal,tlc:{swift:$swiftTLC,pluscal:$pluscalTLC},externalModuleBundle:$externalModuleBundle,timeLimitsSeconds:{fixtureExport:$fixtureExportTimeoutSeconds,pluscalTranslation:$pluscalTranslationTimeoutSeconds,tlc:$tlcTimeoutSeconds}}' > "$output/commands.json"
if run_bounded "$pluscal_translation_timeout_seconds" "$output/translation.stdout" "$output/translation.stderr" java -cp "$jar" pcal.trans -unixEOL "$output/translated/$pluscal_module.tla"; then
  :
else
  status=$?
  if [ "$status" -eq "$timeout_exit" ]; then
    timeout_failure "PlusCal translation" "$case_id" "$pluscal_translation_timeout_seconds" "$output/translation.stdout" "$output/translation.stderr"
  fi
  fail "PlusCal translation failed" "fixture $case_id / PlusCal translation" "pcal.trans to translate the rendered PlusCal module" "translator exited $status; inspect $output/translation.stdout and $output/translation.stderr" "Translator output and inputs were retained; no admission claim was made." "Inspect the rendered source and translator output, then dispatch one fresh hosted candidate run."
fi
for kind in swift pluscal; do
  if [ "$kind" = swift ]; then
    module_name="$(prepare_module "$output/input/swift-lowered.tla" "$output/$kind-tlc")"
    copy_imports "$output/input" "$output/$kind-tlc"
    config_name="swift.cfg"
  else
    module_name="$pluscal_module"
    cp "$output/translated/$module_name.tla" "$output/$kind-tlc/$module_name.tla"
    copy_imports "$output/input" "$output/$kind-tlc"
    config_name="pluscal.cfg"
  fi
  cp "$output/input/$config_name" "$output/$kind-tlc/$config_name"
  module="$output/$kind-tlc/$module_name.tla"; config="$output/$kind-tlc/$config_name"
  case "$kind" in
    swift) tlc_label="Swift TLC graph exploration" ;;
    pluscal) tlc_label="PlusCal TLC graph exploration" ;;
  esac
  if run_bounded "$tlc_timeout_seconds" "$output/$kind-tlc/tlc.stdout" "$output/$kind-tlc/tlc.stderr" java -cp "$jar" tlc2.TLC -workers 1 -fp 1 -deadlock -metadir "$output/$kind-tlc/states" -dump dot,actionlabels "$output/$kind-tlc/graph.dot" -config "$config" "$module"; then
    :
  else
    status=$?
    if [ "$status" -eq "$timeout_exit" ]; then
      timeout_failure "$tlc_label" "$case_id" "$tlc_timeout_seconds" "$output/$kind-tlc/tlc.stdout" "$output/$kind-tlc/tlc.stderr"
    fi
    fail "$tlc_label failed" "fixture $case_id / $kind TLC" "TLC to complete the bounded graph" "TLC exited $status; inspect $output/$kind-tlc/tlc.stdout and $output/$kind-tlc/tlc.stderr" "TLC output and inputs were retained; no admission claim was made." "Inspect retained TLC output, repair the named fixture or lowerer, then dispatch one fresh hosted candidate run."
  fi
  "$root/validation/canonicalize-tlc-dot.rb" "$output/$kind-tlc/graph.dot" "$output/$kind-tlc/canonical-graph.json"
done
semantic_graph() { jq -S '{schema,initialStates,states,edges}' "$1"; }
swift_canonical="$output/swift-tlc/canonical-graph.json"
pluscal_canonical="$output/pluscal-tlc/canonical-graph.json"
if ! cmp -s <(semantic_graph "$swift_canonical") <(semantic_graph "$pluscal_canonical"); then
  swift_counts="$(jq -c '.edgeCounts' "$swift_canonical")"
  pluscal_counts="$(jq -c '.edgeCounts' "$pluscal_canonical")"
  fail "TLC semantic graphs differ" "$case_id" "equal canonical semantic projections (schema, initial states, states, and labeled edges)" "semantic graph content differs; retained edge counts: Swift $swift_counts; PlusCal $pluscal_counts" "Both raw DOT graphs and canonical graphs were retained; no admission claim was made." "Inspect the retained canonical semantic projections and raw DOT graphs, repair the named fixture or lowerer, then dispatch one fresh hosted candidate run."
fi
jq -n --arg id "$case_id" --arg commit "$commit" --arg swiftGraph "$(shasum -a 256 "$output/swift-tlc/graph.dot" | awk '{print $1}')" --arg pluscalGraph "$(shasum -a 256 "$output/pluscal-tlc/graph.dot" | awk '{print $1}')" --arg swiftCanonical "$(semantic_graph "$swift_canonical" | shasum -a 256 | awk '{print $1}')" --arg pluscalCanonical "$(semantic_graph "$pluscal_canonical" | shasum -a 256 | awk '{print $1}')" '{id:$id,resolvedCommit:$commit,conformant:true,differences:[],rawGraphSHA256:{swift:$swiftGraph,pluscal:$pluscalGraph},canonicalGraphSHA256:{swift:$swiftCanonical,pluscal:$pluscalCanonical}}' > "$output/comparison.json"
jq -n --arg translatedModule "$(shasum -a 256 "$output/translated/$pluscal_module.tla" | awk '{print $1}')" --arg translationStdout "$(shasum -a 256 "$output/translation.stdout" | awk '{print $1}')" --arg translationStderr "$(shasum -a 256 "$output/translation.stderr" | awk '{print $1}')" --arg swiftStdout "$(shasum -a 256 "$output/swift-tlc/tlc.stdout" | awk '{print $1}')" --arg swiftStderr "$(shasum -a 256 "$output/swift-tlc/tlc.stderr" | awk '{print $1}')" --arg pluscalStdout "$(shasum -a 256 "$output/pluscal-tlc/tlc.stdout" | awk '{print $1}')" --arg pluscalStderr "$(shasum -a 256 "$output/pluscal-tlc/tlc.stderr" | awk '{print $1}')" '{translatedModuleSHA256:$translatedModule,translatorOutputSHA256:{stdout:$translationStdout,stderr:$translationStderr},tlcOutputSHA256:{swift:{stdout:$swiftStdout,stderr:$swiftStderr},pluscal:{stdout:$pluscalStdout,stderr:$pluscalStderr}}}' > "$output/output-digests.json"
printf '{"swiftLowered":true,"pluscalSource":true,"translatorOutput":true,"swiftTLC":true,"pluscalTLC":true}\n' > "$output/raw-artifacts.json"
