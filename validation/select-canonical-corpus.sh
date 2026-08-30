#!/usr/bin/env bash
set -euo pipefail

candidate_sha="${1:-}"
mode="${2:-}"
[[ "$candidate_sha" =~ ^[0-9a-f]{40}$ ]] || { echo "candidate SHA must be a 40-character lowercase SHA" >&2; exit 2; }
case "$mode" in candidate|admission) ;; *) echo "mode must be candidate or admission" >&2; exit 2 ;; esac

runs="$(gh api --paginate "/repos/RoyalPineapple/SwiftTLA/actions/workflows/ci.yml/runs?head_sha=$candidate_sha&status=success&per_page=100" | jq -s '[.[].workflow_runs[]]')"
eligible_runs="$(jq -c --arg sha "$candidate_sha" --arg mode "$mode" '[.[] | select(
  .head_sha == $sha
    and .status == "completed"
    and .conclusion == "success"
    and ($mode != "admission" or (.event == "push" and .head_branch == "main"))
)]' <<< "$runs")"
[ "$(jq length <<< "$eligible_runs")" -eq 1 ] || { echo "expected one successful CI run for $candidate_sha" >&2; exit 2; }
run="$(jq -c '.[0]' <<< "$eligible_runs")"
run_id="$(jq -r '.id' <<< "$run")"

artifacts="$(gh api --paginate "/repos/RoyalPineapple/SwiftTLA/actions/runs/$run_id/artifacts?per_page=100" | jq -s '[.[].artifacts[]]')"
artifact_name="canonical-corpus-$candidate_sha"
eligible_artifacts="$(jq -c --arg name "$artifact_name" '[.[] | select(.name == $name and .expired == false)]' <<< "$artifacts")"
[ "$(jq length <<< "$eligible_artifacts")" -eq 1 ] || { echo "expected one unexpired $artifact_name artifact in CI run $run_id" >&2; exit 2; }
artifact="$(jq -c '.[0]' <<< "$eligible_artifacts")"

jq -n --argjson run "$run" --argjson artifact "$artifact" '{
  workflowRun: {id:$run.id, attempt:$run.run_attempt},
  artifact: {id:$artifact.id, name:$artifact.name, sha256:$artifact.digest, archiveDownloadURL:$artifact.archive_download_url}
}'
