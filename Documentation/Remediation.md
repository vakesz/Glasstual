# Remediation implementation ledger

The September 2026 remediation code is implemented and covered by the automated
checks below. Runtime and infrastructure acceptance is separate: GUI E2E, live
DumaNet reproduction, minimum-OS sandbox checks and release provisioning are
still blocked or unexercised. Do not describe those checks as passing.

## Decisions

- Preserve current features, persisted identifiers, history, partial downloads,
  Keychain entries, compatible plugins, translations and upstream provenance.
- Disconnect cancels before IRC login; after login, its five-second local bound
  includes the existing two-second graceful QUIT interval.
- Keep TLS verification, sandboxing, strict Swift concurrency and same-Team-ID
  plugin validation. No test disables, isolation escapes or lint suppressions.
- Swift Testing owns unit, integration and out-of-process E2E tests. GUI tests
  use public Accessibility automation, not XCTest/XCUIAutomation.
- New portable configuration files are complete versioned XML snapshots. Merge
  is the default; Restore is explicit and requires preview and a saved backup.
  Legacy sparse files are merge-only.
- Portable export offers **Include connect commands**, off by default, with a
  password warning. Included commands, including an empty list, are imported;
  omitted commands preserve the existing client's commands. No password regex
  guesses which commands are safe.
- Protected local recovery retains commands and certificate references. Neither
  encoder exports Keychain password values or certificate objects. Recovery
  files are private to the app, mode 0600 in a mode-0700 directory, with five
  retained backups. Imported/recovered clients never auto-connect.
- Convenience features such as Settings search remain outside remediation.

## Connection and protocol

- [x] Atomic host initialization with its required Sendable client proxy.
- [x] Owned ordered XPC command consumer and one writer; no network completion
  wait in command or event draining. Queued PONGs retain priority and exemption.
- [x] Actual transport readiness before connected/security delivery; initial
  receive drives establishment without cancelling its deadline prematurely.
- [x] Bounded certificate decisions, cancellation, late-response rejection and
  five-second local close fallback. Exactly-once teardown; no shared-host kill.
- [x] Session/reconnect task ownership, stale callback rejection, termination
  admission guards and total QUIT/close timing.
- [x] Correct client/child title invalidation, closing-state precedence, TLS
  sidebar publication, and shared command validation/action eligibility.
- [x] Right-click menus validate and execute against the explicit clicked row,
  not the previous channel/client. That context survives pointer/focus movement,
  but does not bypass sheets, launch state or command-specific eligibility.
- [x] Rejected pending JOINs return to parted state; manual retries clear the
  failure and send JOIN on the same session after identification. Offline or
  stopping clients cannot mark a channel joining without sending. Nonpending
  channel state is not altered by a 477 response to another command.
- [x] Safe count consumers for JOIN, target batching, nickname/host rendering,
  padding, AWAY, KICK, TOPIC and ZNC. Zero/unlimited meanings are preserved.
- [x] Unified SASL terminal policy and successful authentication state. Tracked
  SCRAM derivation rejects duplicate challenges and retired exchange results.
- [x] Same-host STS endpoint/password identity survives reconnect; cross-host
  redirects do not inherit endpoint PASS credentials.
- [x] CAP effects derive from acknowledged names and satisfied dependencies,
  separate from SASL/ISUPPORT facts, including LS/NEW/DEL and in-flight races.
- [x] Coherent PREFIX/CHANMODES overlay through replacement, empty and withdrawal.
- [x] Admitted batches own response labels; duplicate admission and replay
  ownership are bounded. Nested result delivery waits for replay completion.
- [x] Incremental framing and bounded app input with explicit overload failure.
  Admitted input and complete final ERROR lines remain ordered before teardown.

## History and transcript

- [x] Maximum insertion-ID allocation independent of timestamps, with exhaustion
  failure rather than identifier reuse.
- [x] One FIFO transaction lane for reads/writes/reset/forget/save/close, with
  admission rules and recoverable save/deletion failures.
- [x] Row-level chronological cursors include permanent row identity, so physical
  rows sharing line IDs remain pageable without renumbering or deleting blobs.
  Legacy string cursors still report ambiguity rather than choose arbitrarily.
- [x] Retention removes the actual excess rows, including gapped/duplicate IDs.
  Notifications withdraw a duplicate-index identity only after its final row goes.
- [x] Failed opens preserve the selected database; no arbitrary inferred migration
  or fresh-database fallback. Pending writes survive failed saves/closes.
- [x] Frozen synthetic v1.0.7/model-3 fixture, independent historical encoder and
  provenance under `Tests/Corpora/History`, exercised through reopen/paging/retention.
- [x] Visible local/server history failure state and nondestructive Retry.
  Failed deletions remain explicitly unresolved after a successful save; Retry
  never repeats an old deletion over newly arrived messages. A successful explicit
  clear resolves only that view's deletion failure.
- [x] Older fetch generation checks before mutation, accepted-row cursor updates,
  raw-row/display identity separation, capacity limits and typed failure outcomes.
- [x] Correlated server pages/FAIL/empty outcomes. Without labels, an ambiguous
  timed-out request cannot safely authorize another same-session retry; it stays
  pending until an answer or connection reset instead of guessing exhaustion.
- [x] Ordered drain and all-submissions barrier have distinct contracts and
  cancellation/stop completion. No buffered job starts after pipeline stop.
- [x] Bounded transcript application and replay edits; hidden layout is deferred.
  Append positions and counted duplicate-index updates avoid repeated whole copies.
- [x] Selection endpoint/viewport anchors, restored marks/highlights, and reader
  intent through prepend/trim/restyling. Jump to Present restores bottom-follow.
- [x] Archived/live reaction merging, semantic header restyling, explicit IRC
  color precedence and complete formatted nickname/channel action targets.
- [x] Zero-width regex safety, leading formatting controls, typed renderer options
  and total rendering. Archive envelopes and keys remain unchanged.
- [x] Removed immediate plugin message-cache round trips, unnecessary topic hop,
  duplicate member presentation controller and obsolete row-number drop APIs.
- [x] Weight-only updates do not redraw members. NAMES/WHO publications are batched
  without postponing authoritative membership; relevant render snapshots are cached.
- [x] Actor-owned ordered file logging, rotation, scopes, error throttling and
  termination drain. Slow file I/O does not run on the main actor.
- [x] Inline-media byte/pixel/frame/decoded-memory/concurrency budgets, off-main
  decoding/downsampling, preserved accepted GIF/APNG animation metadata, cached
  attachments and exact retirement/rejection reservation release.

## Configuration, plugins and capabilities

- [x] Exact finite numeric conversion, declaration-level and cross-field
  constraints, and transient number edits committed on submit/focus loss.
- [x] Picker operation identity survives dismissal and rejects stale completion.
  Alternate endpoint edits preserve unrelated drafts and endpoint secret intent.
- [x] Versioned snapshots, validation before mutation, bounded input, Merge/Restore
  preview, stale-preview rejection, visible export results and recovery UI.
- [x] Current live-client backup/commit and imported query policy applied before
  reconciliation. Restore removes extra queries exactly while preserving local
  history/credentials; ordinary server editing keeps its existing query policy.
- [x] Recovery recreates removed clients' commands/certificate references; portable
  re-export sanitizes them again. Migration scratch fields do not create false
  configuration changes after decoding.
- [x] Removed the intermediate keyword cache; preferences publish one current
  consumer snapshot.
- [x] Loaded plugins observe imported settings; Chat Filter compares effective
  values and edits stable rule IDs. Export round trips retain default comparator.
- [x] Shared first-party preference names/defaults, stable loading-aware pane IDs,
  explicit plugin interface version and compatible legacy-marker handling.
- [x] Derived theme/font state and retained unsupported theme bytes on fallback.
- [x] Validated staged add-on replacement, same-location safety and sandbox-correct
  Finder-mediated script installation. Existing installation survives failure.
- [x] Typed regular-file script discovery, deterministic precedence, generation
  guards and rejection of invalid/truncated output before command execution.
- [x] Notification subscription registration/readiness and cancellation ownership;
  synchronous OS sleep/power-off semantics remain intact.
- [x] Exclusive DCC file reservation and actor-owned descriptors/scopes, original
  wire filename, partial identity checks and active/reverse resume commitment.
- [x] Bounded transfer reads and inactivity/acceptance/write waits, ACK framing and
  truthful acknowledged/ACKless completion. Reverse address waiters settle and
  address responses are capped while streaming.
- [x] Completed and fatal rows release byte-I/O descriptors/scopes after quiescence;
  resumable stopped/error rows retain ownership. Partial bytes are not deleted.
- [x] Transfer notification actions use normal destination/navigation operations.
  Notification mute stops its speech/backlog, not explicit speech commands.
- [x] Onboarding SASL, Skip/Finish/Cancel persistence and typed deep-link parsing,
  secure defaults, endpoint-aware reuse confirmation and no external auto-connect.
- [x] Removed redundant SoundPlayer locking, plugin forwarding and app backing
  aliases. Retained public sparse-export entry points and ABI-bound plumbing where
  removing them would create a compatibility break without benefit.

## Tooling and E2E implementation

- [x] Metadata validator failure propagation; Quality CI is lint and format only,
  with build, tests and fixtures run locally before a push.
  Quality also builds the `GlasstualE2E` scheme for testing and runs the loopback
  fixture gate; `scripts/release-validation.sh` requires both steps.
- [x] Release tag/version/embedded-product checks, exact-SHA trusted Quality gate,
  explicit maintenance-release behavior and removal of obsolete service profiles.
  `.github/signing/DeveloperIDProfiles.tar.gz` now holds only the app and IRC
  Connection Host profiles, byte-identical to the originals.
- [x] Non-vacuous catalog inventory, recursive translation argument contracts,
  explicit English runtime tests, spelling fixes and actual generated-symbol checks.
- [x] Fifteen Swift Testing GUI workflows authored; independent Accessibility
  driver/probe, bounded supervision/diagnostics and actual process exit verification.
- [x] Thirteen peer-only fixture modes executed without GUI or personal profiles.
  Added `make e2e-fixtures` for this separate gate. A fixture-client TLS callback
  trap was reproduced under LLDB and fixed with an explicit Sendable closure.
- [x] Production Accessibility identifiers for menus' owning window, transcript,
  input, sidebar, onboarding fields and transfer rows.

## Verification and blocked acceptance

The `build/` result bundles cited below are local-only: `build/` is gitignored,
so these paths exist on the machine that produced them and are not retrievable
from the repository or from CI artifacts.

- Baseline: 1,645 hosted tests passed in `build/Remediation-baseline.xcresult`.
- Original connection regressions failed before the fix in
  `build/Connection-remediation-red.xcresult`.
- Final integrated functional run: 1,927 tests passed, zero skipped/expected
  failures, in `build/Remediation-integrated-22.xcresult`.
- Final sanitizer run: 1,927 tests passed, zero runtime warnings, in
  `build/Remediation-complete-tsan.xcresult`.
- Whole-tree formatting/lint, shellcheck, actionlint and whitespace checks pass.
- E2E scheme build-for-testing passes. All 13 peer-only fixtures passed in
  `build/e2e-fixtures/run-l3CPop`; this is not a GUI workflow result.
- Earlier compilation/fixture failures are retained in their result bundles;
  their corrections did not disable tests or add suppressions.

Outstanding environment/platform gates, not unfinished implementation claims:

- [ ] Execute all 15 GUI E2E scenarios in an unlocked disposable macOS login with
  Accessibility permission. The user confirmed this environment is unavailable.
- [ ] Retest live DumaNet rejection, web authorization, retry, channel Join,
  Disconnect and Quit. A whole-UI freeze still needs an actual main-thread sample;
  fixing the reproduced host stall does not by itself prove that incident resolved.
- [ ] Verify signed macOS 26 bookmark/sandbox/quarantine behavior, real Notification
  Center actions, audible speech/sound and Finder/Quick Look access.
- [ ] Verify third-party DCC/NAT behavior and large real transfers, including
  acknowledgement wrapping beyond 4 GiB.
- [ ] Provision the GUI CI lane and protect the `release` environment with a
  required reviewer; the release job runs on the hosted `xcode-27` image and
  imports its signing material from repository secrets, so there is no separate
  signing runner to provision. Exercise release signing/notarization without
  conflating local lint with those operational checks.

See `E2E.md` and `DCCNotificationVerification.md` for the executable scenarios,
artifacts and platform checklists. Never grant consent automatically or launch
these workflows against personal configuration to turn a blocked gate green.
