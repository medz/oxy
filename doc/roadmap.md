# Road to 1.0

Oxy's intended public model remains `Client`, `Request`, `Response`, `Headers`,
`Body`, policies, lifecycle middleware, typed errors, `Result`, and the
single-package native/Web transports. The pre-1.0 stability policy in the
README still applies. This plan builds on the completed stability work in
[#43](https://github.com/medz/oxy/issues/43); it does not promise a release date.

## Qualification gaps

The starting point is published 0.6.0 and main commit `7633f785`, checked on
2026-10-01. A missing qualification below is not evidence of a runtime defect.
The unreleased development branch now declares Dart 3.12 and checks both
Dart 3.12.0 and stable. Its default non-Web user-agent is version-independent
`oxy`; the historical 0.6.0 observations below describe the published package.

| Area | Current evidence | Required before 1.0 |
| --- | --- | --- |
| Default request cost | Real loopback suites cover five payload/transfer scenarios; #76 remains open. | Measure narrow changes with default policies enabled, preserve behavior, and compare small requests and 64KiB transfers. |
| Minimum SDK | Published 0.6.0 declares Dart 3.10, while required `patchwork 0.5.0` requires 3.12. Development manifest and CI now match Dart 3.12. | Retain effective minimum/stable checks and verify the corrected declaration in the next published package. |
| Public API | 0.3–0.6 deliberately changed core, middleware, headers, cookies, and bodies. | Review and freeze exports, defaults, ownership, replayability, cancellation, and error contracts; document any final changes. Include re-exported upstream types. |
| Platform promises | CI tests VM, Node, and Chrome. The default transport selects native or Web through conditional imports. | Document actual browser restrictions and distinguish compilation/core tests from real transport tests. Add a Flutter consumer and native/browser HTTP consumer smoke checks. |
| Capability metadata | Native capability flags advertise proxy/TLS configuration; the built-in transport exposes no corresponding configuration input. | Make capability claims match the supported API or explicitly document custom transport requirements. |
| Release metadata | Published 0.6.0 sends `oxy/0.3.0`; development uses `oxy` with tested application/header overrides. | Retain the version-independent default and verify package/version metadata for each release. |
| Dependency overlays | A fresh hosted 0.6.0 consumer on Dart 3.13.4 honors RFC850 Retry-After through Patchwork's automatic build hook. | Repeat hosted-consumer checks on the effective minimum SDK and supported build paths; keep provider patches in the published archive. |

## Small release sequence

1. **Correct the SDK contract.** Align the manifest and CI with the dependency
   graph’s Dart 3.12 minimum. Reproduce the published 0.6.0 failure on Dart
   3.10, then qualify Dart 3.12.0 and stable.
2. **Measure default lifecycle overhead.** Complete one independently measured
   slice of #76. Leave signals, status validation, and native uploads for
   separate changes unless their behavior and benefit are demonstrated.
3. **Settle release metadata.** Choose a consistent user-agent policy and
   validate package/version metadata.
4. **Qualify platform contracts.** Document native/Web limitations, correct
   capability claims, and run fresh native, browser, and Flutter consumers.
5. **Freeze the public contract.** Audit exported types and defaults against
   the cookbook and executable examples. Make any necessary breaking changes
   in a focused 0.x minor release with migration examples.
6. **Release a 1.0 candidate.** Validate the frozen contract and packaged
   artifact. Ship 1.0 only when all gates below pass; a candidate label alone
   does not establish stability.

Dependency changes to `ht`, `ocookie`, or `patchwork` must be evaluated against
their exposed contracts and other consumers rather than bundled into a client
optimization. Existing 0.6.0-compatible performance fixes can use patch
releases; a new SDK floor or public contract change needs a minor release.

## 1.0 admission gates

- The public model, defaults, transport ownership, body replayability, and
  middleware/hook ordering have documented contracts and regression coverage.
- Minimum and stable SDK checks pass analysis and the applicable VM, Node, and
  Chrome suites. Unsupported features have explicit documented behavior.
- Benchmarks report their runtime, method, baseline, and samples. Default
  small-request gains must not conceal regressions in larger transfers or
  policy-enabled paths.
- Checked examples and fresh Flutter/native/browser consumers use the public
  API without repository-only setup.
- The package passes the publication dry-run after developer overlays are
  undone. A fresh hosted consumer verifies the published version and automatic
  overlay behavior independently of the development checkout.
- The 1.0 changelog includes migration guidance from the final 0.x release,
  and all known release-blocking defects are resolved.
