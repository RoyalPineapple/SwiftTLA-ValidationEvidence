#!/usr/bin/env bash
set -euo pipefail

checkout="${1:-}"
expected="${2:-}"

[[ "$expected" =~ ^[0-9a-f]{40}$ ]] || { echo "expected validation SHA is not a 40-character lowercase SHA" >&2; exit 2; }
actual="$(git -C "$checkout" rev-parse --verify HEAD^{commit})"
[[ "$actual" =~ ^[0-9a-f]{40}$ ]] || { echo "checked-out validation revision is not a 40-character lowercase SHA" >&2; exit 2; }
[ "$actual" = "$expected" ] || { echo "checked-out validation revision $actual differs from GitHub revision $expected" >&2; exit 2; }
git -C "$checkout" show-ref --verify --quiet refs/remotes/origin/main || { echo "origin/main is unavailable in the validation checkout" >&2; exit 2; }
git -C "$checkout" merge-base --is-ancestor "$actual" refs/remotes/origin/main || { echo "validation revision $actual is not an ancestor of origin/main" >&2; exit 2; }
printf '%s\n' "$actual"
