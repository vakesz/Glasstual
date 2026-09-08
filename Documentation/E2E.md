# Real-app E2E gate

`make e2e-fixtures` builds the helper and exercises all 13 TCP/TLS/DCC fixture
modes with synthetic clients on loopback. It needs no Accessibility grant, no
disposable-account attestation and no external `timeout` command: each mode
bounds itself with monotonic deadlines. `ScenarioKind.hasFixtureTest` is the only
list of modes; the script iterates `GlasstualE2EHarness list-fixtures`.

`make e2e` runs a Swift Testing bundle outside Glasstual. It launches the actual
Debug app executable with `Process`, resolves `NSRunningApplication` by that
child's PID, drives public Accessibility menus, and connects the app's sandboxed
IRC XPC service to a scripted IPv4 loopback listener. There is no app import,
`@testable`, XCTest, XCUIAutomation, injected controller, or private app command
channel.

## What has been executed, and what has not

Read this before quoting anything below as coverage; nothing else in this file
repeats these limits.

- **The GUI matrix has never run.** No disposable GUI login is available, no
  consent was asserted or granted, and no app, personal preferences or external
  IRC network was exercised. Every GUI case, AX identifier, window title, menu
  title, button label, file-panel control and status string named below is a
  runtime contract the first provisioned run must confirm. A mismatch fails the
  case.
- **Compilation is not runtime verification.** The harness and the Swift Testing
  matrix compile for arm64 macOS 26 with complete strict concurrency and default
  MainActor isolation, and SwiftLint strict passes over both. That says nothing
  about AppKit's runtime AX tree, the sandbox suite import, or macOS 26 runtime
  behavior on the newer SDK used to build.
- **The fixture gate has run.** All 13 peer-only modes passed against real local
  Network.framework clients, after the TLS self-test callback was made explicitly
  `Sendable` and client teardown waited for the peer's observed QUIT. The harness
  and E2E scheme were rebuilt and the gate re-ran after the UUID-scoped DCC
  selector and view-identifier follow-ups; no part of the harness is
  source-checked only. Coverage: split and coalesced registration, invalid
  command/order/EOF rejection, channel replies, denied-JOIN recovery, raw Smiley
  stimulus ordering, exact burst counts, full and partial DCC bytes with
  cumulative ACKs, TLS accept/reject/stall, snapshot validation, sample filtering.
- **Fixtures do not stand in for the UI.** History and onboarding fixtures verify
  network inputs, not persistence or UI. The Smiley fixture does not test plugin
  loading or conversion; the helper neither imports nor calls the plugin. Burst
  fixtures count names and messages on the client socket and cannot establish app
  responsiveness or member-list rendering. No fixture-only case tests Settings UI.
- **OS behavior is a manual gate**, listed under *Platform gates*. No automated
  case claims notification permission or action coverage. Absence of crash logs is
  never proof of a clean exit, and green fixture-only tests never waive a blocked
  platform check.

## Implemented matrix

Swift Testing serializes fifteen GUI cases and thirteen fixture-only self-tests.
Every invocation gets a fresh `scenarios/<kind>-<UUID>/` directory with its own
deadlines, wire markers, logs and evidence. GUI cases launch a fresh app process
with a synthetic server, fresh client/server identifiers, scratch defaults suite
and review directory. No credentials, proxy, automatic connection or automatic
reconnection are seeded; certificate validation is explicitly enabled. Onboarding
cases start with an empty client list and an unfinished onboarding flag: Skip
leaves the list empty, Finish creates the loopback server through the
custom-server form with automatic connection explicitly off.

| GUI case | Actions and required observations |
| --- | --- |
| `rejectionRetry` | Reject plaintext registration; assert the transcript and disconnected title; reconnect in the same PID; observe welcome and PONG; Disconnect with exact QUIT/EOF within five seconds; Quit. |
| `repeatedRejection` | Repeat rejection and manual recovery three times in one PID; require three transcript occurrences and four registrations; Quit while connected with exact QUIT/EOF. |
| `channelMessaging` | Connect; type `/join #e2e` in the native editor; observe the joined-channel transcript; type a message; receive a fixture reply; type `fixture: E2E_TYPED_REPLY`; observe the acknowledgement; Quit while connected. This is a conversational reply, not an IRCv3 reply-tag or context-menu test. |
| `channelDenied` | Join `#other`; attempt `#retry`; receive numeric 477 and assert its transcript. Return to `#other`; type synthetic NickServ IDENTIFY; receive 900/ACCOUNT/MODE +r and service notices; invoke `AXShowMenu` on the unjoined `#retry` row. Require `#other` still selected before pressing the enabled contextual Join Channel item. The peer requires an exact second `JOIN #retry` on the same connection; the UI must activate `#retry` and show its own-JOIN response and fixture transcript. Quit while connected. |
| `historyRelaunch` | Complete the message/reply flow and Quit cleanly. Launch a second owned app process with the same synthetic suite and review directory, without reseeding. Select the unjoined `#e2e` row; require disconnected status plus the saved outgoing message, incoming reply and acknowledgement in the native transcript. Require another clean Quit. |
| `settingsSnapshot` | Connect and Disconnect cleanly; open Settings through its menu. Change the confirmation toggle; open Export Configuration; require Include connect commands off; press Export in the option sheet, then use the native save panel. Require a complete XML archive with connect commands absent. Change the toggle back; import through the native open panel; inspect the preview; press Merge. Require restoration and success UI. Open and cancel Preview Recovery; reset confirmation to false; close Settings; Quit cleanly. |
| `onboardingSkip` | Start with no servers; enter synthetic nickname/real name/alternate nickname; Continue to Appearance; press Skip. Verify the accepted nickname and real name through Advanced > Identity in Settings. Quit, relaunch the same scratch suite, require onboarding to stay dismissed, verify identity again, Quit normally. No network peer runs for this case. |
| `onboardingFinish` | Enter the synthetic identity; Continue through Appearance; require the app's visible pre-denied notification status; Continue to Network. Filter the network list; select Custom Server; enter the fixture's loopback address/port; turn TLS/SASL/Connect when finished off; Finish. Manually Connect and require registration through the real IRC XPC service; type `/quit E2E_QUIT` and require exact QUIT/EOF. Quit, relaunch, require the persisted server disconnected and onboarding dismissed, verify identity, Quit normally. |
| `pluginSmiley` | Join `#e2e`. Open Settings from the application menu; select Add-ons > Smiley Converter; set Enable Smiley Converter off/on/off. After each setting, return to the channel and request a fresh raw `:-)` message from the IRC fixture. Require literal/converted U+1F60A/literal transcript text. |
| `dccSuccess` | Request a real CTCP DCC SEND offer; select its transfer row; press Start Transfer; choose a unique scratch destination through the native folder panel. Require 100,003 processed bytes, complete status, peer ACK/closure, exact destination bytes and a SHA-256 artifact. Quit normally. |
| `dccCancel` | Accept the same real DCC offer. The peer sends 37,003 bytes and stalls. Require that exact processed-byte count; press Cancel Transfer; require stopped status and peer closure; verify the retained partial's bytes and SHA-256. Quit normally. |
| `burstResponsiveness` | Join `#e2e`; request a paced burst of 10,000 unique names and 5,000 messages over 100 batches. Open/close Settings and return to the channel three times while streaming, obtaining a distinct IRC acknowledgement after each switch. Require the final transcript marker, 10,002 members including the two original members, peer counts and continuous independent AX responsiveness. |
| `tlsAccept` | Present the self-signed certificate; leave the real certificate panel unanswered for three seconds; press Continue through AX; observe IRC registration/welcome/PONG; Quit while connected. |
| `tlsRejectRetry` | Leave the certificate panel unanswered; press Cancel through AX; require disconnected state and zero peer-side IRC registration; reconnect in the same PID; accept the new certificate panel; observe registration/welcome/PONG; Quit while connected. |
| `tlsStall` | Receive but never answer ClientHello; hold four seconds with independent AX probing; Disconnect; require transport closure and disconnected UI within five seconds; Quit. No IRC registration is allowed. |

Every GUI case requires the original app `Process` to report
`terminationReason == .exit` and `terminationStatus == 0`. A signal, crash,
nonzero exit, cleanup termination or missing peer completion fails. Connected
Quit checks the connected title immediately before opening the Quit menu and
requires both app exit and exact peer QUIT/EOF within five seconds of AXPress.
History and onboarding also check the second process's exit reason, status and
distinct PID; its `relaunch-` artifacts, AX deadlines, probe heartbeat and Quit
deadline cannot be satisfied by the first launch's markers. A failing case
terminates and unregisters its own app, peer and probe, so the next case is not
blocked by a leftover instance.

The peer imports `Tests/Corpora/TLS/LoopbackTestIdentity.p12` with
`kSecImportToMemoryOnly`, resolved as `../TLS/LoopbackTestIdentity.p12` relative
to the directory containing `E2E_FIXTURE`; it never imports that identity into a
Keychain. The app's production XPC TLS implementation is unchanged.

## Required setup

Use a disposable macOS 26+ Apple Silicon GUI login with Xcode 27, not the account
holding your IRC identities. The Debug overrides redirect the app's shared
preferences and review-managed directories but **do not isolate standard
defaults, Keychain, every group-container path, or XPC preferences**; an
alternate `HOME` does not fix the sandbox or Keychain. Do not copy real
preferences into the fixture. Keep the account free of user plugins, login
scripts, IRC credentials and real server configurations.

1. Provision development signing and the profiles for the app and IRC XPC
   service, and build the generated project normally. Do not disable signing or
   sandboxing, re-sign the app ad hoc, or replace the XPC service for E2E.
2. Launch and quit the Debug app once in that login to provision its sandbox
   container. The helper must be able to write the synthetic plist under
   `~/Library/Containers/<bundle-id>/Data/Library/Preferences`; macOS may require
   Full Disk Access for the launching terminal or helper.
3. Build the `GlasstualE2E` scheme for testing to produce the helper at a stable
   path, normally `DerivedData/Build/Products/Debug/GlasstualE2EHarness`. The
   watchdog uses that compiled helper, not a shell command waiting on a build, so
   this bootstrap precedes the script.
4. Grant that executable Accessibility access in System Settings > Privacy &
   Security > Accessibility, using the same signed executable and path on every
   run; temporary `swiftc` output is a compile check, not the consent identity.
   TCC may instead attribute access to the responsible terminal or test runner —
   grant it if macOS asks, then rerun the helper preflight. Missing permission is
   exit status 2, a setup failure, never a skipped or passing test.
5. Keep the session unlocked and visible, quit existing Glasstual instances, and
   do not touch its menus during a run. The driver launches in English so the
   scoped menu and exact title assertions are deterministic.

For `onboardingFinish`, the operator must have denied notifications for the
signed app in this login beforehand: the scenario requires the app's visible
denied-status message before leaving Notifications. It presses no OS consent
button, alters no TCC state and simulates no authorization; missing this setup
fails the case before the permission-requesting Continue.

`make e2e` regenerates the project first, like every other build target:

```sh
E2E_DISPOSABLE_USER_CONSENT=YES make e2e \
  E2E_APP=/absolute/path/to/Debug/Glasstual.app \
  DERIVED_DATA=/absolute/path/to/DerivedData \
  E2E_OUTPUT=/absolute/path/to/e2e-artifacts
```

Only the consent variable is required; the rest have defaults, and `E2E_HELPER`
can override the stable helper path. The consent variable is an operator
attestation, not proof the account is disposable, and the script refuses to
proceed without it. The driver also refuses an app without the compiled Debug
review-override names, or a bundle ID already running, and the script verifies
the app signature and sandbox entitlement before the helper may launch it. Do not
run while another worker holds the build lock.

The script always refreshes build-for-testing products before
`test-without-building`, so the scheme environment and run directory cannot come
from an old run, and it copies the already-built signed helper into the unique run
directory for the supervisor alone, so rebuilding cannot overwrite the executing
watchdog. AX preflight and the UI driver still run from the stable `E2E_HELPER`
path.

The scheme's test environment reads `E2E_APP`, `E2E_HELPER`, `E2E_FIXTURE`,
`E2E_OUTPUT` and `E2E_DISPOSABLE_USER_CONSENT` from build settings the supervisor
passes; each is identical on every run. The per-run directory is deliberately not
among them, because a build setting that changes every run changes the build
description and forces a full rebuild. The script records it in
`$E2E_OUTPUT/current-run`, the test bundle reads it from there (an explicit
`E2E_RUN_DIRECTORY` in the environment still wins) and hands it to each helper
child.

### Direct launch boundary

The driver launches `<E2E_APP>/Contents/MacOS/<CFBundleExecutable>` as a child
`Process` with `-AppleLanguages (en) -AppleLocale en_US`, fresh review-suite and
review-directory values, and only HOME, USER, LOGNAME, PATH and TMPDIR inherited
from the runner; DYLD and test-bundle injection variables are excluded. The
signed executable runs its production entry point and normal
NSApplicationMain/SwiftUI lifecycle, with the app sandbox and embedded XPC service
unchanged. The parent registers the PID immediately after spawn, before waiting
for startup, and retains the `Process` through Quit to read the actual exit reason
and status. This path claims no LaunchServices, open-document, URL-delivery or
Finder-relaunch coverage; the first provisioned run must confirm container
initialization, XPC launch/signing, scene startup, activation and AX visibility
under it.

## Targets and isolation

`GlasstualE2ETests` is `bundle.unit-test` with explicitly empty `TEST_HOST` and
`BUNDLE_LOADER`, no dependency on the app binary or app frameworks, importing
Foundation, Darwin for kernel process identity, and Swift Testing.
`GlasstualE2EHarness` is a signed, unsandboxed command-line tool with `supervise`,
`scenario`, `peer`, `probe`, `fixture-test`, `preflight` and `list-fixtures`
modes, linking AppKit, ApplicationServices, Network, Security and CryptoKit. The
app keeps its sandbox and embedded service signing. Both targets use Swift 6,
complete strict concurrency and default MainActor isolation. DCC bytes are
generated deterministically in memory, so no resource copy phase is needed.

The scheme builds the app and helper, then tests the standalone bundle.
`@Suite(.serialized)`, nonparallel testable configuration and
`-parallel-testing-enabled NO` prevent simultaneous GUI scenarios. The supervisor
holds a per-login `flock` guard at `/private/tmp/glasstual-e2e-<uid>.lock`,
verifies its owner, file type, link count and mode, refuses a held or unsafe
guard, retains the descriptor through diagnostics and cleanup, and never unlinks
the inode.

Network callbacks hand events to the peer process's main actor and do not block
the GUI driver. AX calls run in the driver and probe processes, never in the test
runner or supervisor. The script execs the supervisor, which polls children every
100 ms instead of blocking in `wait`. Every child the harness launches — build
commands, codesign, preflight, driver, peer, app — is registered by its parent
before any wait, and the Xcode-owned runner registers itself at test entry.
Kernel process start seconds and microseconds identify owned PIDs, without
launching `ps`. If registration cannot be written, the parent terminates its own
child and fails rather than leaving an untracked process running.

### Deadlines

The supervisor has a 3,000-second absolute monotonic deadline. Builds get 600
seconds, each codesign command 15, preflight 10, test startup/execution 2,340,
and each case 180 starting before the helper's preflight — 240 for DCC cases. The
peer gets 230. Each fixture-only assertion gets eight seconds, twenty for the
paced burst's final marker, under one 90-second bound for the whole fixture run.
Each rejection recovery iteration gets 30 seconds and its own completion marker.

The supervisor scans every case's deadlines and failure marker on each poll and
requires exactly one completion per GUI and fixture case, rejecting missing,
duplicate and unexpected cases; that check is also what proves the test bundle's
scenario list still matches `ScenarioKind`. A stuck child cannot stop the
supervisor from terminating owned processes and exiting, and INT/TERM enter
bounded cleanup. When a scenario fails, the helper clears every deadline marker it
armed, so a failed assertion is never reported as a watchdog timeout.

Each AX evaluation has one absolute monotonic deadline of at most two seconds
covering traversal, matching, attribute reads and actions, with at most 1,500
nodes. Every AX call checks that deadline before and after, and sets a messaging
timeout no greater than 500 ms or the remaining time. Snapshots have their own
two-second deadline covering their reads and output. Ordinary assertions retry
missing state for up to 20 seconds; a slow AX evaluation fails rather than
repeatedly consuming that budget. The supervisor reads the evaluation deadline
from outside the driver and can kill a driver stuck inside AX. The last successful
evaluation latency is retained as an artifact.

A separate helper probes the app's AXWindows and a window's AXTitle every 500 ms,
including deliberate idle gaps and unanswered certificate panels. It checks app
PID/start-time identity and keeps a two-second heartbeat deadline armed while
sleeping, so a dead probe cannot silently remove responsiveness coverage; only
count and latency enter evidence. The driver must observe a normal probe exit and
completion marker before Quit, so the five-second Quit deadline covers shutdown
rather than probing an exiting app. History and onboarding relaunches have their
own probe and prefix-specific deadlines; diagnostics check both launch records but
sample only a currently owned live PID.

Disconnect has one shared **five-second** deadline, starting immediately before
AXPress on the Disconnect item and covering the disconnected title/subtitle, exact
QUIT and EOF, and peer exit. The TLS stall case requires transport closure instead
of QUIT because registration never began. Evidence includes elapsed monotonic
time, and the Swift Testing assertion requires no more than five seconds; external
timeout reporting allows 250 ms plus a 100 ms polling interval, not extra passing
time. The peer binds only `127.0.0.1:0`, the kernel selects the port, and the
listener stays open across recovery attempts. No external IRC server is used.

## Accessibility contract

The app exposes `main-window` and `channel-transcript`. The driver scopes the
transcript lookup to that window, checks its AXTextArea role and reads its native
AXValue, without inspecting private SwiftUI storage or invoking app methods.
`MainWindow.updateTitle()` exposes the actual title and subtitle joined by `, ` in
the window's AXTitle, so status checks read that identified window and never
accept an unrelated static-text or sidebar node. The exact connected value is
`E2E, e2euser \u{00B7} e2e.local`, where `\u{00B7}` is the UI's middle dot; this
excludes Connecting, Reconnecting, Logging On, Disconnecting and Disconnected.
Disconnected checks require `E2E, Disconnected \u{00B7} e2euser`: teardown clears
the selected endpoint and negotiated host, and the configured nickname remains.
Menus are located from the app's AXMenuBar; after pressing the selected
AXMenuBarItem the driver searches only the direct items of that opened menu, and
requires enabled state before acting.

Channel typing requires `message-input` under `main-window`. Every editor lookup —
role and emptiness, the typed value before Return, the empty value after
submission — is scoped to that identified window. The driver focuses through AX,
posts Unicode and Return events to the owned PID, and never changes the clipboard.
The channel's connected-title prefix includes `#e2e`, `E2E` and `e2euser` with no
Connecting/Disconnected status; member counts and channel modes may follow. The
denied-JOIN case uses the equivalent prefixes for `#other` and `#retry`.

Sidebar lookup matches `Channel #retry, Channel Not Joined` or its joined
equivalent, allowing only the composed badge suffix after a comma. It searches
inside `server-list` under the identified main window, then walks at most eight
parents to the native AXRow; selection uses AXSelected. Contextual joining checks
the row's supported actions and performs AXShowMenu, never selecting the target
row to make a main-menu command work, and context-menu lookup excludes AXMenuBar
descendants. Unsupported AXShowMenu, a selection change during menu presentation,
or a missing enabled contextual Join Channel fails explicitly; no main-menu
fallback is allowed.

Transcript, editor and sidebar-identifier lookup prunes unrelated AXList, AXTable
and AXOutline descendants after checking the container's own identifier, and
diagnostic role snapshots prune collection contents too, so the 1,500-node budget
is not spent on thousands of member rows.

Settings lookup scopes the confirmation checkbox and configuration controls to
their window. File panels use AXSheet, Save/Open/Go buttons, the focused Go to
Folder field and the labeled Save As field; import checks the preview's changed
preference label and presses its Merge button. Certificate buttons are scoped to
the window containing the exact localized English invalid-certificate prompt for
`127.0.0.1`, and only its enabled Continue or Cancel is pressed — the harness
never enables an always-trust checkbox.

This branch uses English visible labels for native menus, Start/Cancel Transfer,
terminal transfer status and the transient configuration export/import sheets,
and modifies neither those sheets nor their generated String Catalog symbols.
Settings navigation uses the visible General/Add-ons/Advanced rows, radio segments
or a meaningfully labeled native page picker, and exact loaded plugin pane/toggle
text. Onboarding's network search uses its public `Search networks` placeholder to
make Custom Server visible without unbounded scrolling. None of these lookups
invokes a SwiftUI model or plugin method.

### View selector contract

These identifiers are attached to existing user-facing views, not to a test-only
object or command endpoint. Adding them changed only view accessibility metadata
and the DCC row's accessibility grouping — not layout, bindings, actions or
transfer behavior.

| Identifier | Public AX contract |
| --- | --- |
| `server-list` | Sidebar List container holding the existing composed server/channel labels and native AXRow ancestors. |
| `onboarding-nickname` | Editable nickname field; AXValue is the visible nickname. |
| `onboarding-real-name` | Editable real-name field; AXValue is the visible real name. |
| `onboarding-alternate-nickname` | Editable alternate-nickname field. |
| `network-address` | Custom server address field in NetworkPickerView. |
| `network-port` | Custom server port field in NetworkPickerView. |
| `file-transfer-row-<uuid>` | Accessible row-content container. `<uuid>` is the existing controller's `uniqueIdentifier`, also the List's selection tag. Selection acts on its bounded native AXRow ancestor. |
| `file-transfer-filename-<uuid>` | Existing filename text in that row; AXValue remains the displayed filename. |
| `file-transfer-status-<uuid>` | Existing localized status text in that row, including completed and stopped states. |
| `file-transfer-bytes-<uuid>` | Existing formatted-size text: the localized transfer-progress label plus formatted total size, with an exact decimal processed-byte AXValue. It survives completion and cancellation, unlike the transient progress bar. |

The DCC row uses `.contain` rather than `.combine`, keeping filename,
size/progress and status individually accessible. No hidden diagnostic view was
added and the displayed text and layout are unchanged; the size element's label
retains its formatted total size so the exact count has progress context for
VoiceOver.

The helper finds filename IDs with the `file-transfer-filename-` prefix whose
visible value is exactly `e2e-transfer.bin`, validates the UUID suffix and
requires exactly one matching identity. It then resolves that row and reads only
its UUID-suffixed byte and status properties, re-resolving the same identity as
the UI updates. There is no unqualified or global status fallback: duplicate
fixture filenames on different UUIDs fail rather than picking an arbitrary
transfer.

## Watchdog and artifacts

Each invocation creates a mode-700 unique run directory whose xcresult is
`GlasstualE2E.xcresult` inside it, never `build/Glasstual.xcresult`. On failure it
keeps build/test/helper stdout and stderr logs, signature evidence, the last
attempted step, a bounded AX role/known-identifier snapshot when the app responds,
wire assertion markers, and PID/exit-status/timing evidence. Raw preference files,
Keychain data, arbitrary AX values, IRC payload dumps, screenshots and broad
unified logs are never collected. The Settings case deliberately retains its
synthetic export as `synthetic-configuration.plist`; the helper bounds the read to
16 MiB and checks the XML format/version, confirmation value and sole synthetic
loopback server, without reading the user's preference files or dumping the
archive into logs. This is another reason the disposable-account restriction is
mandatory.

Wire diagnostics record only known fixture values. USER validates every argument,
QUIT validates the fixture leaving comment, and registration order is enforced.
After registration only fixture PONG, exact optional user/channel MODE and WHO
queries, and scenario-appropriate JOIN/PRIVMSG/QUIT commands are allowed.
Duplicate PONG, QUIT before PONG, missing channel replies, commands after QUIT,
unknown commands or mismatched arguments fail without printing received content,
including PASS/AUTHENTICATE or unexpected identity values. The denied-JOIN case
accepts only the literal synthetic NickServ IDENTIFY command, provisions no
Keychain credential and contacts no real service; evidence records the known
authentication steps, exact retry target and connection count, never received
authentication content.

DCC data is 100,003 bytes with byte `i` equal to
`UInt8(truncatingIfNeeded: i * 31 + 7)`. The cancel peer sends only its first
37,003 bytes and holds the connection open until the UI cancels. Peer evidence
requires cumulative big-endian acknowledgements and closure. The GUI helper reads
only `dcc-download/e2e-transfer.bin` in that case's directory, requires an exact
full or prefix match, records count plus SHA-256 in `dcc-file-evidence`, and never
writes the destination payload on the app's behalf. Both offers use a real
loopback listener announced by CTCP through the real IRC connection, with manual
DCC acceptance and a loopback manual IP address, avoiding automatic download and
external address-discovery services.

Burst evidence includes three distinct UI-switch markers and the peer's 100-batch
completion; the server sends 100 names and 50 messages every 150 ms, the final 366
closes NAMES, and the independent probe stays armed throughout. Before
terminating an owned live app on failure, the supervisor attempts a
one-second `/usr/bin/sample` with a three-second external limit. It checks the
app's PID/start-time against the ownership ledger before sampling and registers
the sampler as another owned child. Output goes to a nonblocking pipe, never
sample's default output file; at most 128 KiB is retained in memory and only up to
80 main-thread frames from allowed app/system modules survive filtering. Paths,
quoted strings, addresses, headers and binary-image lists are not persisted.
`process-sample.txt` records filtered frames and sampler status, or
unavailability. Sampling failure never delays cleanup beyond its bound or turns a
failed run green. The sanitizer has local self-tests; sampling an actually stuck
GUI app has not been exercised.

The watchdog tracks only registered processes, checking PID plus process start
time before signaling, and never adopts existing app instances. Cleanup uses TERM,
then KILL only if necessary. Any live process requiring cleanup, any forced kill,
timeout, missing completion marker or helper failure makes the run fail. There is
no `killall`, process-name kill or global defaults reset. The parent obtains the
app PID from `Process.run()` before inspecting any NSRunningApplication state,
eliminating the previous unregistered LaunchServices-await interval. The platform
owns XPC service lifecycle; the supervisor does not kill services by name. Forced
cleanup is always a failure and cannot replace the observed `.exit`/zero-status
Quit assertion.

Scratch suites and review directories stay in the disposable account for
diagnosis. Remove the account after testing, or inspect a case's
`scratch-suite.txt` before removing only its scratch data. The harness never
deletes baseline preferences, Keychain entries or prior result bundles.

## Platform gates

These are **manual validation requirements**, not authored scenarios and not
passing results. No synthetic notification delegate callback, private app call,
injected authorization status or direct transfer-controller action substitutes for
them.

- Verify the signed app's real notification permission flow from not-determined to
  denied, then separately an operator-granted state. Record the OS prompt and the
  app's visible authorization status. Keep the automated onboarding Finish run in
  the denied state; the harness neither grants nor revokes permission.
- Deliver an eligible real fixture notification with the app foregrounded and
  backgrounded, using Notification Center's actual body click and Accept button
  rather than an in-app facsimile. Verify the intended server/channel or DCC
  transfer gains focus and that acceptance uses the real destination picker when
  needed.
- Repeat Notification Center actions for active, completed and removed DCC
  transfers and a destroyed IRC client. Stale actions must not start another
  transfer or route to the wrong identity. Record the resulting native row state
  and full/partial fixture bytes where applicable.
- Verify OS delivery with permission denied, and mute while a notification is in
  flight. Exercise real notification sound and speech completion/cancel, checking
  that explicit speech is not mistaken for notification speech.
- Inspect signed-app quarantine and other OS-created extended attributes on the
  chosen full and partial DCC files, and exercise persisted or stale destination
  bookmarks across relaunch. No quarantine vulnerability or fix is inferred from
  the helper's byte and ACK tests.
- Run the signed app on minimum-supported macOS 26. Third-party active and reverse
  DCC, NAT/router traversal, ACKless completion and transfers crossing the 32-bit
  ACK wrap remain interoperability gates, not coverage of the small active
  loopback receiver scenarios.

Retain build/signing identity, OS version, action steps and bounded synthetic
evidence for these checks. `Documentation/DCCNotificationVerification.md` holds
the broader DCC/notification checklist and its separately recorded local evidence.

## Required gate

Quality CI runs lint and format checks only; building, the Swift Testing suite
and `make e2e-fixtures` run locally before a push, as AGENTS.md's hand-off list
requires, because hosted macOS build minutes are reserved for the signed
release. None of that is the real-app E2E gate: a generic runner is not assumed
to have an interactive login, Accessibility consent or safe storage isolation.

Before merging connection or UI lifecycle changes, run `make e2e` in the
provisioned disposable GUI login and retain the unique result directory. A
dedicated runner can report that gate as a required status once its signing,
AX/TCC, account lifecycle and artifact access are provisioned. Until then require
the recorded manual run; do not equate green unit CI with E2E completion. Missing
setup is a blocked gate, not a waiver.
