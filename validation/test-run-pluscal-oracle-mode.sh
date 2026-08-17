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
      {name: "FiniteSetTheorems", path: "library/FiniteSetTheorems.tla", source: {repository: "https://github.com/tlaplus/tlapm.git", githubRepository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5"}, sha256: "484bf0f9ab6a69ef45f7282f7f92dcf1e6ae139e44117b0d5a4427635818e773"},
      {name: "Folds", path: "modules/Folds.tla", source: {repository: "https://github.com/tlaplus/CommunityModules.git", githubRepository: "tlaplus/CommunityModules", commit: "a8068a4c21ed76b339b9a2aa6de69d78f64f6422"}, sha256: "aa59063fd600bb640b2ae24dc85ef770277ef5bf7955092b76b8b471790086da"},
      {name: "Functions", path: "modules/Functions.tla", source: {repository: "https://github.com/tlaplus/CommunityModules.git", githubRepository: "tlaplus/CommunityModules", commit: "a8068a4c21ed76b339b9a2aa6de69d78f64f6422"}, sha256: "b54ff63b7c76c327525c17c188d5f9f5e53d92f3fd701f5e2ba54f0f54391063"},
      {name: "NaturalsInduction", path: "library/NaturalsInduction.tla", source: {repository: "https://github.com/tlaplus/tlapm.git", githubRepository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5"}, sha256: "08f52420cdaaf11292ed366782b5ce5b596bb7cbe789526a1cfd8806dbf98624"},
      {name: "TLAPS", path: "library/TLAPS.tla", source: {repository: "https://github.com/tlaplus/tlapm.git", githubRepository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5"}, sha256: "9afe54984062748a0568966434cc0945d682f8cd89fdbc38f73b5579751b0c55"},
      {name: "WellFoundedInduction", path: "library/WellFoundedInduction.tla", source: {repository: "https://github.com/tlaplus/tlapm.git", githubRepository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5"}, sha256: "6f2f274c2e987d1edcf004d8e37b053f1f82b912e66d6a51bae0af8012ddcbec"}
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
