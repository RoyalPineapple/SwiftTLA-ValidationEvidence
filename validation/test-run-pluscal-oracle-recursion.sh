#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runner="$root/validation/run-pluscal-oracle.sh"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
mkdir "$temporary/bin"
ln -s "$root/validation/test-fixtures/pluscal-oracle-swift-list.sh" "$temporary/bin/swift"
chmod +x "$root/validation/test-fixtures/pluscal-oracle-child-capture.sh" "$root/validation/test-fixtures/pluscal-oracle-swift-list.sh"

commit="$(git -C "$root" rev-parse HEAD)"
capture="$temporary/children.args"
set +e
PATH="$temporary/bin:$PATH" \
PLUSCAL_ORACLE_CAPTURE="$capture" \
PLUSCAL_ORACLE_CHILD_RUNNER="$root/validation/test-fixtures/pluscal-oracle-child-capture.sh" \
"$runner" \
  --case all \
  --checkout "$root" \
  --commit "$commit" \
  --requested-ref candidate \
  --mode candidate \
  --validation-commit "$commit" \
  --output "$temporary/output" \
  --canonical-corpus "$temporary/corpus"
status=$?
set -e
[ "$status" -eq 1 ]

arguments="$(tr '\0' '\n' < "$capture")"
[ "$(grep -Fx -- '--case' <<< "$arguments" | wc -l | tr -d ' ')" -eq 8 ]
[ "$(grep -Fx -- '--checkout' <<< "$arguments" | wc -l | tr -d ' ')" -eq 8 ]
[ "$(grep -Fx -- '--commit' <<< "$arguments" | wc -l | tr -d ' ')" -eq 8 ]
[ "$(grep -Fx -- '--canonical-corpus' <<< "$arguments" | wc -l | tr -d ' ')" -eq 8 ]
[ "$(grep -Fx -- "$temporary/corpus" <<< "$arguments" | wc -l | tr -d ' ')" -eq 8 ]
for id in \
  scope-binding-substitution \
  formal-operator-values \
  simultaneous-assignment \
  structured-record-functions \
  procedure-call-return \
  boulanger-upstream-port \
  kvsnap-upstream-port \
  voteproof-upstream-port; do
  grep -Fx -- "$id" <<< "$arguments" >/dev/null
done
