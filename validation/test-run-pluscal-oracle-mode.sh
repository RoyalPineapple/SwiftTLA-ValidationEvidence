#!/usr/bin/env bash
set -euo pipefail

runner="$(cd "$(dirname "$0")" && pwd)/run-pluscal-oracle.sh"
root="$(cd "$(dirname "$0")/.." && pwd)"
jq -e '.schema == "SwiftTLAExternalValidation" and .version == 3' "$root/validation/pluscal-oracle.json" >/dev/null
grep -Fq 'if [ "$mode" = admission ] && [ "$case_id" != all ]; then' "$runner"
grep -Fq ' --mode candidate --validation-commit ' "$runner"
grep -Fq 'if [ "$case_id" = kvsnap-upstream-port ] || [ "$case_id" = voteproof-upstream-port ]; then tlc_timeout_seconds=300; fi' "$runner"
grep -Fq 'fixture_registry_timeout_seconds=600' "$runner"
grep -Fq 'run_bounded "$fixture_registry_timeout_seconds" "$suite/fixture-list.stdout"' "$runner"
[ "$(grep -Fc 'swift run --jobs 1 --package-path "$root/validation/pluscal-oracle-harness"' "$runner")" -eq 2 ]
grep -Fq 'is_canonical_corpus_fixture()' "$runner"
grep -Fq '(.sourceOwnedCases // []) | index($fixture) != null' "$runner"
grep -Fq 'stage_canonical_corpus_fixture()' "$runner"
grep -Fq '.swiftTLASHA == $commit' "$runner"
grep -Fq '"$child_runner" --case "$id"' "$runner"
grep -Fq ' --output "$output/$id" --canonical-corpus "$canonical_corpus" || status=$?' "$runner"
grep -Fq 'swift_config_path=' "$runner"
grep -Fq 'pluscal_config_path=' "$runner"
grep -Fq 'cp "$canonical_corpus/$swift_config_path" "$input/swift.cfg"' "$runner"
grep -Fq 'cp "$canonical_corpus/$pluscal_config_path" "$input/pluscal.cfg"' "$runner"
! grep -Fq 'stage_voteproof_tlaps_modules' "$runner"
! grep -Fq 'external-module-provenance.json' "$runner"

fixtures="$root/validation/pluscal-oracle-harness/Sources/SwiftTLAValidationFixtures"
registry="$fixtures/FixtureRegistry.swift"
exporter="$root/validation/pluscal-oracle-harness/Sources/pluscal-oracle-harness/main.swift"
[ ! -e "$fixtures/BoulangerWitness.swift" ]
[ ! -e "$fixtures/KVsnapWitness.swift" ]
[ ! -e "$fixtures/VoteProofWitness.swift" ]
grep -Fq 'id: "boulanger-upstream-port"' "$registry"
grep -Fq 'id: "kvsnap-upstream-port"' "$registry"
grep -Fq 'id: "voteproof-upstream-port"' "$registry"
! grep -Fq 'CONSTANT Value =' "$registry"
grep -Fq 'specification().compile().renderedPlusCalBundle()' "$registry"
grep -Fq 'specification().compile().renderedTLAModuleBundle()' "$exporter"
! grep -Fq 'specification().tlaBundle' "$exporter"

perl -0ne '
  while (/\blet\s+(\w+)(?:\s*:\s*[^=]+)?\s*=\s*(?:SharedVar|LocalVar)\b/g) {
    $name = $1;
    $tail = substr($_, pos);
    $tail =~ /\n[ \t]*\Q$name\E[ \t]*\n/ or die "unregistered runtime handle $name in $ARGV\n";
  }
' "$fixtures"/*Witness.swift
