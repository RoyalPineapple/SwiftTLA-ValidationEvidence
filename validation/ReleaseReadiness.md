# Release readiness

SwiftTLA commit `610283d522ee7fc42a8bad3a7c8397cdfdebac87` passed external PlusCal admission.

## Source corpus

- SwiftTLA CI run: [33315483371](https://github.com/RoyalPineapple/SwiftTLA/actions/runs/33315483371)
- Artifact: `canonical-corpus-610283d522ee7fc42a8bad3a7c8397cdfdebac87`
- Artifact digest: `sha256:c19cc620a73f48af9223d8679bf56c386a5736348d49087f7630f4b7322b2759`
- Archive verification: passed

## External admission

- ValidationEvidence commit: `47d18d2fa39cab0a3e27f2bac2836bc783c6267f`
- Admission run: [33316783152](https://github.com/RoyalPineapple/SwiftTLA-ValidationEvidence/actions/runs/33316783152)
- Mode: `admission`
- Requested and resolved SwiftTLA commit: `610283d522ee7fc42a8bad3a7c8397cdfdebac87`
- Artifact: `pluscal-oracle-610283d522ee7fc42a8bad3a7c8397cdfdebac87-33316783152-1`
- Artifact digest: `sha256:500d1c4d8c3443ab5b0c34f276042f8ff31b0d297cce0866a38affdc4026a16e`

All declared fixtures completed with equal raw and canonical graphs and no reported differences:

- `scope-binding-substitution`
- `formal-operator-values`
- `simultaneous-assignment`
- `structured-record-functions`
- `procedure-call-return`
- `boulanger-upstream-port`
- `kvsnap-upstream-port`
- `voteproof-upstream-port`

The audit reported no missing or unexpected fixtures.

## Toolchain

- TLC: `1.8.0`
- `tla2tools.jar`: `sha256:eabd140a70f49eb9305a3bd3f3df944eddf87e5a90d329789085f8953a80533a`
- Java: Eclipse Temurin `17.0.19+10`
