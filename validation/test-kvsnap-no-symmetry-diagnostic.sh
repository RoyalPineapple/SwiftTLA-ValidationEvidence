#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
registry="$root/validation/pluscal-oracle-harness/Sources/SwiftTLAValidationFixtures/FixtureRegistry.swift"
runner="$root/validation/run-pluscal-oracle.sh"
workflow="$root/.github/workflows/pluscal-kvsnap-no-symmetry-diagnostic.yml"

grep -Fq 'id: "kvsnap-no-symmetry-diagnostic"' "$registry"
grep -Fq 'of: "SYMMETRY SymmTxId\\n", with: ""' "$registry"
! sed -n '/public static let fixtures = \[/,/^    ]/p' "$registry" | grep -Fq 'kvsnapNoSymmetryDiagnostic'
grep -Fq 'tlc_timeout_seconds="${TLC_TIMEOUT_SECONDS:-90}"' "$runner"
grep -Fq 'a positive integer number of seconds' "$runner"
grep -Fq -- '--case kvsnap-no-symmetry-diagnostic' "$workflow"
grep -Fq 'TLC_TIMEOUT_SECONDS: "300"' "$workflow"
grep -Fq -- '--mode candidate' "$workflow"
