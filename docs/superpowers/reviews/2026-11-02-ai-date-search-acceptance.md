# AI date-search candidate acceptance

2026-11-02. Candidate **v1.4.17/build24**, branch `codex/ai-error-feedback`,
based on verified v1.4.16 source `067e84e24050c7ccc9eef8952ab18a74a5e5293e`.

**Product, UX, focused QA and final independent whole source review passed.
Exact staged-source quality, protected integration, signed public delivery and
installed interaction remain pending. This candidate is unshipped and does not
complete the whole product goal.**

The [design](../specs/2026-11-02-ai-date-search-failures.md) distinguishes completed
no-date output, operational failure and unavailable on-device selection. Failure
retains the editable draft and ends progress. Existing native Return resubmits
once; current success closes the editor and sends one existing date action.
Cancellation is silent, and late results cannot change a newer request.

Direct editor bindings and synchronous Preferences callbacks drive the actual
model. Current preference reload reconciles settings; owned hide and actual view
removal discard the search. Hidden preparation cannot authorize submission, and
repeated visible Show preserves the current request. Existing keyboard routing,
provider policy, parsing, permissions, event handling and geometry are preserved.

| Boundary | Accepted focused evidence |
| --- | --- |
| Client classification | Behavioral RED followed by 11 methods/23 cases passing. Synthetic real decoder/parser and injected on-device paths distinguish supported no-date output from operational errors and cancellation. Eight response-shape cases were strengthened after the first RED; that stronger path is not claimed as the original RED. |
| Request ownership | 15 methods/34 unchanged cases passing after 20 failed cases reproduced cancellation, revision and stale-completion defects. Cleanup also covers canceled observers, actual producer completion and continued draining after failures. |
| Actual editor/settings/panel | Eight methods/17 unchanged native cases passed, with zero failures, skips or expected failures. Six cases previously failed at direct settings, reload and root removal; all passed after the corresponding production wiring. |
| Rendering and controls | All three static messages remain accessible and fit the existing 300pt body width; real editor retry, progress/dismiss state and close behavior are exercised in the native suite. This is fixture geometry evidence, not bitmap or VoiceOver acceptance. |
| Native execution integrity | Resolve, native test and both metadata extraction commands exited zero. A positively observed owned test host exited naturally. Fresh valid process inventories confirmed owned process/group/path absence; all 15 source inputs, both pins, branch, HEAD and empty index stayed unchanged during the focused run. |
| Fixture corrections | Initial premature menu cleanup and later unassociated callback issues are retained as fixture failures. The accepted fixture sets the insertion caret, awaits actual owned menu-close notification and captures immutable state synchronously before yielding; assertions execute in the originating test. Actual task joins remain distinct from watchdogs. |
| CI integration | The prepared serial AI phase and exact 8/17 manifest match the actual native graph. Independent source/offline tooling review passed. A later actual-metadata check exposed a valid warning under a Passed parameter case. Independent source review accepted the narrow shared parser correction; 23 focused offline methods pass, and unchanged actual 8/17 metadata passes with the exact parameter warning preserved. The seven-file gate proposal is integrated; full exact-source quality remains mandatory. |

External evidence remains under
`build/validation/diagnostics-fixture-implementation.yucljzsb/`.
The accepted client, model and integration records are respectively under
`ai-client-source-preparation.rfiocjo6/`,
`ai-model-green-source.fzz9a1s0/` and
`ai-integration-green-source.f284ravj/focused-integration-green.6m9xs8hl/`.
The accepted integration RED is
`ai-native-attribution-correction.7fj20j6c/focused-integration-red.ryilfhx4/`.
Original logs, result bundles, hashes and failed fixture attempts remain preserved.

| Role | Bounded decision |
| --- | --- |
| Product — Lead | Passed: useful fixed error distinctions and retained drafts preserve successful date navigation. |
| UX — Lead | Passed at owned fixture scope: readable accessible feedback, preserved targets, explicit resubmission and silent cancellation. |
| Code — independent reviewer | Passed: the final 26-file source candidate was fully reviewed against A1–A8, with no Critical, Important or Minor findings and exact unchanged before/after source identities. Whole quality and delivery remain separate gates. |
| QA — Lead | Passed at focused scope: client11/23, model15/34 and actual native8/17. Ordinary exact staged-source and hosted quality remain mandatory. |

One user-interactive-to-Default QoS runtime warning remains in the native keyboard
fixture at its event retrieval call; ten raw compiler warning lines were retained.
This is not warning-free acceptance or evidence of a production crash/performance
cause. The checker must preserve warnings without counting them as test cases.

Latest verified public and installed distribution is v1.4.16/build23. No live AI
service or private calendar was queried by these fixtures. Live on-device model
readiness, signed installed interaction, physical keyboard/VoiceOver, macOS 14,
workload comparisons and longer endurance remain open. The original other-machine
crash is unexplained; the real restart check is user-deferred.
