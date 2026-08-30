# PlusCal validation evidence

This repository owns the external PlusCal translator/TLC lifecycle. Candidate
mode accepts a SwiftTLA branch, tag, or SHA, resolves it once, and uses the
immutable checkout SHA for every subsequent operation. The workflow downloads
the single unexpired canonical corpus artifact from that revision's successful
`canonical-corpus-export` job. Admission requires a successful `main` push.
The workflow verifies the archive digest and retains its artifact ID, workflow
run identity, export-job identity, timestamps, size, and digest. It also retains per-fixture input,
TLC, and canonical comparison evidence as a GitHub Actions artifact. Upstream
corpus models are authored only in SwiftTLA; this repository stages their
verified bundles unchanged. The small harness contains focused regression
witnesses that have no corpus model. Each `case.json` identifies its source as
`canonical-corpus` or `validation-harness`.

Candidate mode records pre-merge evidence. Admission mode records post-merge
evidence. It requires an immutable 40-character SwiftTLA SHA, verifies the
exact checkout, proves that commit belongs to the `main` history, and retains
it with the evidence. The workflow verifies that its exact ValidationEvidence
SHA belongs to `origin/main` and supplies that SHA to every fixture run.
Admission executes exactly the stable fixture contract in
`validation/pluscal-oracle.json`.

`--case all` always writes `pluscal-differential-audit/result.json`. It runs the declared contract directly, passes the immutable checkout, SHA, configurations, and corpus path to every child, and records missing or unexpected fixtures as well as per-fixture graph results. The audit cannot pass by silently checking a smaller corpus.

Each fixture directory retains the resolved SwiftTLA and validation-repository SHAs; tool version, jar digest, and Java version; exact commands/options; source and output digests; raw translator and TLC stdout/stderr; raw TLC DOT graphs; canonical graphs; and the exact graph comparison. The workflow runs Eclipse Temurin `17.0.19+10`, the same JVM pinned by SwiftTLA's finite-graph checks. Evidence directories are fresh and never reused. Canonical graph comparison requires equal initial states, states, and labeled edge multiplicities. Each canonical edge records its source state, action label, target state, and occurrence count.
The DOT reader requires TLC's complete graph envelope and accepts every state,
edge, and rank record. It rejects malformed records, duplicate state IDs,
unknown references, missing closure, and trailing data.

Every external operation has a deliberate wall-clock bound: fixture export is limited to 180 seconds, PlusCal translation to 30 seconds, and each TLC graph exploration to 90 seconds. KVsnap and VoteProof use a retained-evidence 300-second exception because their bounded imported-module graphs exceed the common cap on the one-worker hosted runner. The runner starts each operation in its own macOS process group, terminates that group on timeout, retains partial stdout/stderr, and writes the normal six-field diagnostic with the operation, fixture, limit, and safe next action.
