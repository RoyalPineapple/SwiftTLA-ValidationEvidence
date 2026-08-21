#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runner="$root/validation/run-pluscal-oracle.sh"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

commit="$(git -C "$root" rev-parse HEAD)"
corpus="$temporary/corpus"
output="$temporary/evidence"
child="$temporary/child-runner.sh"
log="$temporary/children.tsv"
mkdir -p "$corpus"
printf '{"schema":"CanonicalCorpusExportV1","swiftTLASHA":"%s","cases":[]}' "$commit" > "$corpus/manifest.json"

cat > "$child" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  case "$1" in
    --case) case_id="$2"; shift 2 ;;
    --checkout) checkout="$2"; shift 2 ;;
    --commit) commit="$2"; shift 2 ;;
    --requested-ref) requested_ref="$2"; shift 2 ;;
    --mode) mode="$2"; shift 2 ;;
    --validation-commit) validation_commit="$2"; shift 2 ;;
    --canonical-corpus) canonical_corpus="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    *) exit 2 ;;
  esac
done
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$case_id" "$checkout" "$commit" "$requested_ref" "$mode" "$validation_commit" "$canonical_corpus" >> "$PLUSCAL_ORACLE_CHILD_LOG"
mkdir -p "$output"
printf '{"conformant":true}' > "$output/comparison.json"
CHILD
chmod +x "$child"

PLUSCAL_ORACLE_CHILD_LOG="$log" PLUSCAL_ORACLE_CHILD_RUNNER="$child" \
  "$runner" --case all --checkout "$root" --commit "$commit" --requested-ref "$commit" \
  --mode admission --validation-commit "$(printf 'a%.0s' {1..40})" \
  --canonical-corpus "$corpus" --output "$output"

expected="$(jq -r '.requiredCases[].fixtureID' "$root/validation/pluscal-oracle.json" | sort)"
actual="$(cut -f1 "$log" | sort)"
[ "$actual" = "$expected" ]
[ "$(awk -F '\t' -v checkout="$root" -v commit="$commit" -v corpus="$corpus" '$2 != checkout || $3 != commit || $4 != commit || $5 != "candidate" || $7 != corpus { print; exit 1 }' "$log")" = "" ]
jq -e '.mode == "admission" and .conformant == true' "$output/pluscal-differential-audit/result.json" >/dev/null
