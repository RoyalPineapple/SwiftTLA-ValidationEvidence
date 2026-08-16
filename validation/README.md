# PlusCal validation evidence

This repository owns the external PlusCal translator/TLC lifecycle. The workflow accepts a SwiftTLA branch, tag, or SHA, records the resolved immutable SHA, exports its public `AlgorithmConformance` fixtures, and retains per-fixture input, TLC, and canonical comparison evidence as a GitHub Actions artifact.

Candidate mode is pre-merge evidence: it accepts a branch, tag, or SHA and never makes an admission claim. Admission is post-merge evidence: it accepts `main` only, resolves and retains that exact immutable SwiftTLA SHA, and fails closed unless the discovered fixtures are exactly the stable contract in `validation/pluscal-oracle.json`. No per-merge mapping edit is required.

`--case all` always writes `pluscal-differential-audit/result.json`. It records missing or unexpected fixtures as well as per-fixture graph results, so the audit cannot pass by silently checking a smaller corpus.

Each fixture directory retains the resolved SwiftTLA and validation-repository SHAs; tool version, jar digest, and Java version; exact commands/options; source and output digests; raw translator and TLC stdout/stderr; raw TLC DOT graphs; canonical graphs; and the exact graph comparison. Evidence directories are fresh and never reused.

Every external operation has a deliberate wall-clock bound: fixture export is limited to 180 seconds, PlusCal translation to 30 seconds, and each TLC graph exploration to 90 seconds. These fixtures are bounded and normally complete in seconds; three minutes leaves room for the observed 111.5-second cold Swift package export while still bounding a six-fixture suite below its 45-minute job limit. The runner starts each operation in its own macOS process group, terminates that group on timeout, retains partial stdout/stderr, and writes the normal six-field diagnostic with the operation, fixture, limit, and safe next action.
