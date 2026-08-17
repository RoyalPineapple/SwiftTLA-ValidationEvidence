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

fixtures="$root/validation/pluscal-oracle-harness/Sources/SwiftTLAValidationFixtures"
perl -0ne '
  while (/\blet\s+(\w+)(?:\s*:\s*[^=]+)?\s*=\s*(?:SharedVar|LocalVar)\b/g) {
    $name = $1;
    $tail = substr($_, pos);
    $tail =~ /\n[ \t]*\Q$name\E[ \t]*\n/ or die "unregistered runtime handle $name in $ARGV\n";
  }
' "$fixtures"/*Witness.swift
