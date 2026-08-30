#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
selector="$root/validation/select-canonical-corpus.sh"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
mkdir "$temporary/bin"

cat > "$temporary/bin/gh" <<'MOCK'
#!/usr/bin/env bash
case "${!#}" in
  *'/actions/workflows/ci.yml/runs?'*) cat "$MOCK_RUNS" ;;
  *'/artifacts?'*) cat "$MOCK_ARTIFACTS" ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$temporary/bin/gh"

sha="$(printf 'a%.0s' {1..40})"
runs="$temporary/runs.json"
artifacts="$temporary/artifacts.json"
write_run() {
  jq -n --arg sha "$sha" --arg event "$1" --arg branch "$2" '{workflow_runs:[{id:17,run_attempt:2,head_sha:$sha,status:"completed",conclusion:"success",event:$event,head_branch:$branch}]}' > "$runs"
}
write_artifact() {
  jq -n --arg name "canonical-corpus-$sha" --arg digest "sha256:$(printf 'b%.0s' {1..64})" '{artifacts:[{id:23,name:$name,digest:$digest,expired:false,archive_download_url:"https://example.invalid/corpus.zip"}]}' > "$artifacts"
}
select_corpus() {
  PATH="$temporary/bin:$PATH" MOCK_RUNS="$runs" MOCK_ARTIFACTS="$artifacts" "$selector" "$sha" "$1"
}

write_run pull_request feature
write_artifact
select_corpus candidate | jq -e '.workflowRun == {id:17,attempt:2} and .artifact.id == 23' >/dev/null
if select_corpus admission >/dev/null 2>&1; then
  echo "admission accepted a pull-request run" >&2
  exit 1
fi

write_run push main
select_corpus admission >/dev/null
jq '.workflow_runs += .workflow_runs' "$runs" > "$temporary/duplicate-runs.json"
mv "$temporary/duplicate-runs.json" "$runs"
if select_corpus admission >/dev/null 2>&1; then
  echo "selection accepted ambiguous CI runs" >&2
  exit 1
fi

write_run push main
jq '.artifacts += .artifacts' "$artifacts" > "$temporary/duplicate-artifacts.json"
mv "$temporary/duplicate-artifacts.json" "$artifacts"
if select_corpus admission >/dev/null 2>&1; then
  echo "selection accepted ambiguous artifacts" >&2
  exit 1
fi
