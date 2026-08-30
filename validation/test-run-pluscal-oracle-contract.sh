#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "$0")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
git clone --quiet "$source_root" "$temporary/validation"
root="$temporary/validation"
git -C "$root" update-ref refs/remotes/origin/main HEAD
runner="$root/validation/run-pluscal-oracle.sh"

validation_commit="$(git -C "$root" rev-parse HEAD)"
candidate="$temporary/candidate"
git init --quiet -b main "$candidate"
git -C "$candidate" config user.name Test
git -C "$candidate" config user.email test@example.com
git -C "$candidate" commit --quiet --allow-empty -m candidate
candidate_commit="$(git -C "$candidate" rev-parse HEAD)"
corpus="$temporary/corpus"
output="$temporary/evidence"
child="$temporary/child-runner.sh"
log="$temporary/children.tsv"
mkdir "$temporary/bin"
ln -s "$root/validation/test-fixtures/pluscal-oracle-swift-list.sh" "$temporary/bin/swift"
mkdir -p "$corpus"
printf '{"schema":"CanonicalCorpusExport","swiftTLASHA":"%s","cases":[]}' "$candidate_commit" > "$corpus/manifest.json"

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
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$case_id" "$checkout" "$commit" "$requested_ref" "$mode" "$validation_commit" "$canonical_corpus" "$output" >> "$PLUSCAL_ORACLE_CHILD_LOG"
mkdir -p "$output"
printf '{"conformant":true}' > "$output/comparison.json"
CHILD
chmod +x "$child"

PATH="$temporary/bin:$PATH" PLUSCAL_ORACLE_CHILD_LOG="$log" PLUSCAL_ORACLE_CHILD_RUNNER="$child" \
  "$runner" --case all --checkout "$candidate" --commit "$candidate_commit" --requested-ref "$candidate_commit" \
  --mode admission --validation-commit "$validation_commit" \
  --canonical-corpus "$corpus" --output "$output"

expected="$(jq -r '.requiredCases[].fixtureID' "$root/validation/pluscal-oracle.json" | sort)"
actual="$(cut -f1 "$log" | sort)"
[ "$candidate_commit" != "$validation_commit" ]
[ "$actual" = "$expected" ]
[ "$(awk -F '\t' -v checkout="$candidate" -v candidateCommit="$candidate_commit" -v validationCommit="$validation_commit" -v corpus="$corpus" -v output="$output" '$2 != checkout || $3 != candidateCommit || $4 != candidateCommit || $5 != "candidate" || $6 != validationCommit || $7 != corpus || $8 != output "/" $1 { print; exit 1 }' "$log")" = "" ]
jq -e --arg candidate "$candidate_commit" --arg validation "$validation_commit" '.schema == "SwiftTLAPlusCalDifferentialAudit" and .version == 1 and .mode == "admission" and .resolvedCommit == $candidate and .validationCommit == $validation and .conformant == true' "$output/pluscal-differential-audit/result.json" >/dev/null
