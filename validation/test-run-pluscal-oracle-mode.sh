#!/usr/bin/env bash
set -euo pipefail

runner="$(cd "$(dirname "$0")" && pwd)/run-pluscal-oracle.sh"
root="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq 'if [ "$mode" = admission ] && [ "$case_id" != all ]; then' "$runner"
grep -Fq ' --mode candidate --validation-commit ' "$runner"
grep -Fq 'if [ "$case_id" = kvsnap-upstream-port ]; then tlc_timeout_seconds=300; fi' "$runner"
grep -Fq 'fixture_registry_timeout_seconds=600' "$runner"
grep -Fq 'run_bounded "$fixture_registry_timeout_seconds" "$suite/fixture-list.stdout"' "$runner"
[ "$(grep -Fc 'swift run --jobs 1 --package-path "$root/validation/pluscal-oracle-harness"' "$runner")" -eq 2 ]
grep -Fq 'stage_voteproof_tlaps_modules()' "$runner"
grep -Fq 'if [ "$case_id" = voteproof-upstream-port ]; then stage_voteproof_tlaps_modules; fi' "$runner"
grep -Fq 'external-module-provenance.json' "$runner"

manifest="$root/validation/external-modules/voteproof-tlaps.json"
jq -e '
  .schema == "SwiftTLAExternalModuleBundleV1"
    and .fixtureID == "voteproof-upstream-port"
    and (.modules | sort_by(.name) == [
      {name: "FiniteSetTheorems", path: "library/FiniteSetTheorems.tla", source: {repository: "https://github.com/tlaplus/tlapm.git", githubRepository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5"}, sha256: "ba288f643559652a855f1ecb8c45e9de81f82409037e73681dd925ccd9123bf0"},
      {name: "Folds", path: "modules/Folds.tla", source: {repository: "https://github.com/tlaplus/CommunityModules.git", githubRepository: "tlaplus/CommunityModules", commit: "a8068a4c21ed76b339b9a2aa6de69d78f64f6422"}, sha256: "3fa7a06cbef5a1981f1ad021bdb58f9790f76b072e4fe585bc3f9d8b8dcb7bb4"},
      {name: "Functions", path: "modules/Functions.tla", source: {repository: "https://github.com/tlaplus/CommunityModules.git", githubRepository: "tlaplus/CommunityModules", commit: "a8068a4c21ed76b339b9a2aa6de69d78f64f6422"}, sha256: "3ca67b609e4e934e02ab2ba618699439f211c956495d8047e0fed0560ac3c301"},
      {name: "NaturalsInduction", path: "library/NaturalsInduction.tla", source: {repository: "https://github.com/tlaplus/tlapm.git", githubRepository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5"}, sha256: "dcb3411b6ed5510bc8b68b823b3153d5220b48b8f0e22a4c848a7d403e3585d5"},
      {name: "TLAPS", path: "library/TLAPS.tla", source: {repository: "https://github.com/tlaplus/tlapm.git", githubRepository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5"}, sha256: "aae5df72d522bdb047e467365ae9c7c15c163ea8027920460e075435e0035ff1"},
      {name: "WellFoundedInduction", path: "library/WellFoundedInduction.tla", source: {repository: "https://github.com/tlaplus/tlapm.git", githubRepository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5"}, sha256: "cf06fa60a5bc6139e061075a7593517f8e89ac6aa223f921ede74879056329f3"}
    ])
' "$manifest" >/dev/null

fixtures="$root/validation/pluscal-oracle-harness/Sources/SwiftTLAValidationFixtures"
vote_proof="$fixtures/VoteProofWitness.swift"
registry="$fixtures/FixtureRegistry.swift"
grep -Fq 'public var tlaValue: TLAValue { .string(rawValue) }' "$vote_proof"
[ "$(grep -Fc 'guard case .string(let rawValue) = formalValue else { return nil }' "$vote_proof")" -eq 2 ]
grep -Fq 'CONSTANT Value = {\"v1\", \"v2\"}' "$registry"
grep -Fq 'CONSTANT Acceptor = {\"a1\", \"a2\", \"a3\"}' "$registry"
grep -Fq 'CONSTANT Quorum = {{\"a1\", \"a2\"}, {\"a1\", \"a3\"}, {\"a2\", \"a3\"}, {\"a1\", \"a2\", \"a3\"}}' "$registry"

perl -0ne '
  while (/\blet\s+(\w+)(?:\s*:\s*[^=]+)?\s*=\s*(?:SharedVar|LocalVar)\b/g) {
    $name = $1;
    $tail = substr($_, pos);
    $tail =~ /\n[ \t]*\Q$name\E[ \t]*\n/ or die "unregistered runtime handle $name in $ARGV\n";
  }
' "$fixtures"/*Witness.swift
