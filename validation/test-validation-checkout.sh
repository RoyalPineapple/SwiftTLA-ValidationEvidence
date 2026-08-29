#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
verify="$root/validation/verify-validation-checkout.sh"
runner="$root/validation/run-pluscal-oracle.sh"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

git init --bare "$temporary/origin.git" >/dev/null
git init -b main "$temporary/source" >/dev/null
git -C "$temporary/source" config user.name Test
git -C "$temporary/source" config user.email test@example.com
git -C "$temporary/source" commit --allow-empty -m first >/dev/null
first="$(git -C "$temporary/source" rev-parse HEAD)"
git -C "$temporary/source" commit --allow-empty -m second >/dev/null
git -C "$temporary/source" remote add origin "$temporary/origin.git"
git -C "$temporary/source" push -u origin main >/dev/null
git --git-dir="$temporary/origin.git" symbolic-ref HEAD refs/heads/main
git clone "$temporary/origin.git" "$temporary/checkout" >/dev/null
git -C "$temporary/checkout" checkout --detach "$first" >/dev/null

[ "$("$verify" "$temporary/checkout" "$first")" = "$first" ]
if "$verify" "$temporary/checkout" "$(git -C "$temporary/source" rev-parse HEAD)" >/dev/null 2>&1; then
  echo "validation checkout accepted a different GitHub SHA" >&2
  exit 1
fi
if "$verify" "$temporary/checkout" invalid >/dev/null 2>&1; then
  echo "validation checkout accepted a malformed GitHub SHA" >&2
  exit 1
fi

git -C "$temporary/checkout" config user.name Test
git -C "$temporary/checkout" config user.email test@example.com
git -C "$temporary/checkout" commit --allow-empty -m unpublished >/dev/null
unpublished="$(git -C "$temporary/checkout" rev-parse HEAD)"
if "$verify" "$temporary/checkout" "$unpublished" >/dev/null 2>&1; then
  echo "validation checkout accepted a revision outside origin/main" >&2
  exit 1
fi

candidate="$(git -C "$root" rev-parse HEAD)"
set +e
"$runner" --case all --checkout "$root" --commit "$candidate" --requested-ref "$candidate" \
  --mode candidate --validation-commit invalid --canonical-corpus "$temporary/corpus" \
  --output "$temporary/runner-output"
status=$?
set -e
[ "$status" -eq 2 ]
jq -e '.whatFailed == "Invalid validation SHA"' "$temporary/runner-output/diagnostic.json" >/dev/null
