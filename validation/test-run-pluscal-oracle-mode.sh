#!/usr/bin/env bash
set -euo pipefail

runner="$(cd "$(dirname "$0")" && pwd)/run-pluscal-oracle.sh"
grep -Fq 'if [ "$mode" = admission ] && [ "$case_id" != all ]; then' "$runner"
grep -Fq ' --mode candidate --validation-commit ' "$runner"
grep -Fq 'if [ "$case_id" = kvsnap-upstream-port ]; then tlc_timeout_seconds=300; fi' "$runner"
grep -Fq 'fixture_registry_timeout_seconds=600' "$runner"
grep -Fq 'run_bounded "$fixture_registry_timeout_seconds" "$suite/fixture-list.stdout"' "$runner"
