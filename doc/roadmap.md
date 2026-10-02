# Road to 1.0

Oxy's intended public model remains `Client`, `Request`, `Response`, `Headers`,
`Body`, policies, lifecycle middleware, typed errors, `Result`, and the
single-package native/Web transports. The pre-1.0 stability policy in the
README still applies. This plan builds on the completed stability work in
[#43](https://github.com/medz/oxy/issues/43); it does not promise a release date.

## Qualification gaps

The starting point was published 0.6.0 and main commit `7633f785`. Published
0.7.0 corrected the SDK declaration and user-agent contract; independent hosted
consumers verified both on Dart 3.12.0 and 3.13.4. The following table separates
that completed work from remaining gates and current development coverage.
A missing qualification is not evidence of a runtime defect.

| Area | Current evidence | Required before 1.0 |
| --- | --- | --- |
| Default request cost | Real loopback suites cover five payload/transfer scenarios; #76 remains open. | Measure narrow changes with default policies enabled, preserve behavior, and compare small requests and 64KiB transfers. |
| Minimum SDK | Published 0.7.0 declares Dart 3.12, matching `patchwork 0.5.0`; fresh hosted consumers passed minimum/stable checks. | Retain effective minimum/stable checks. |
| Public API | 0.3–0.6 deliberately changed core, middleware, headers, cookies, and bodies. The [contract baseline](api-contracts.md) records defaults, state/ownership, upstream exports, lazy-body hooks, and the JSON error boundary. | Explicitly decide remaining error/export contracts before freezing; document any final changes with migration examples. |
| Platform promises | VM/Node/Chrome Dart tests and real loopback HTTP regressions are complemented by [fresh Flutter macOS/Web applications](../tool/qualification/README.md) and observable socket closure. | Qualify additional promised Flutter targets/build modes, packaged browser artifacts, and supported streaming-upload paths; preserve exact version/target evidence. |
| Capability metadata | Development flags match native configuration inputs and Web's request-streaming probe. | Keep feature claims aligned with the supported API and runtime. |
| Release metadata | Published 0.7.0 uses `oxy`; fresh hosted consumers verified application/header overrides. | Retain the version-independent default and verify package/version metadata for each release. |
| Dependency overlays | Fresh hosted Dart consumers passed automatic RFC850 overlay checks on minimum/stable SDKs. Cold Flutter macOS compilation can use the original parser before the final mapping is updated. Oxy's own Retry-After normalization avoids that ordering dependency. | Qualify remaining upstream parser/cookie contracts and retain provider patches. [#80](https://github.com/medz/oxy/issues/80) separately tracks removal only after an upstream release is verified. |

## Small release sequence

1. **Correct SDK and release metadata contracts — completed in 0.7.0.**
   Minimum/stable CI and independent hosted consumers cover the actual SDK
   floor, package metadata, and version-independent user-agent.
2. **Qualify transport lifecycle and platform contracts.** Correct capability
   claims, stop pending body reads on cancellation and timeout, and document
   ownership. Retain fresh macOS/Web consumers and qualify the additional
   promised Flutter targets/build modes and packaged browser artifacts.
3. **Measure default lifecycle overhead.** Complete one independently measured
   slice of #76 using default policies and real loopback comparisons. No
   performance improvement is claimed by the transport-contract fixes.
4. **Freeze the public contract.** Audit exported types and defaults against
   the cookbook and executable examples. Make any necessary breaking changes
   in a focused 0.x minor release with migration examples.
5. **Release a 1.0 candidate.** Validate the frozen contract and packaged
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
