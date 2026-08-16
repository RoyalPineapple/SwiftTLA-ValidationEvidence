# PlusCal validation evidence

This repository owns the external PlusCal translator/TLC lifecycle. The workflow accepts a SwiftTLA branch, tag, or SHA, records the resolved immutable SHA, exports its public `AlgorithmConformance` fixtures, and retains per-fixture input, TLC, and canonical comparison evidence as a GitHub Actions artifact.

Candidate mode is evidence only. Admission mode fails closed unless `validation/pluscal-oracle.json` contains six reviewed K1--K6 fixture mappings for the resolved SHA. Evidence directories are fresh and are never reused.
