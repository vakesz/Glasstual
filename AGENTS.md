# Repository guidance

Glasstual is a macOS 26+ IRC client, arm64 only, written entirely in Swift 6
with `SWIFT_STRICT_CONCURRENCY=complete`. The Objective-C port finished: there
are no `.h`, `.m`, `.c` or `.mm` files left, and none should come back.

## Architecture

- SwiftUI owns user-facing layout, navigation, forms and scene presentation.
  AppKit is a capability adapter only: keep it narrow, stateless and owned by
  the feature that needs it. Before removing an adapter, preserve keyboard
  commands, focus, selection, drag-and-drop, accessibility, restoration and
  plugin behavior. The deliberate adapters are the main-window responder and
  restoration shell, TextKit input/transcript editing, the transcript reaction
  popover, dock-tile rendering and the pre-scene blocking alert path.
- Layout is by feature: `Sources/App/{Application,Protocol,Preferences,
  Features/<Feature>,UI,Localization,Resources}`. `Sources/App/README.md`
  describes each directory's scope and the conventions; a feature owns its
  controllers, views, models and strings together, and nothing goes back
  under a former Objective-C class folder.
- Model closed domain state with enums, option sets and value types. Persist
  and archive with `Codable`; reach for `NSSecureCoding` only where an
  `NSXPCInterface` allowlist requires it.
- The app runs `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Parsers, wire
  types, and anything an XPC service shares opt out with `nonisolated`. Do not
  reach for `@unchecked Sendable`, `nonisolated(unsafe)` or
  `MainActor.assumeIsolated` to settle an isolation error; move the boundary
  instead. See "Isolation rules" below for what the gate enforces.
- Preferences are typed `PreferenceKey` declarations under
  `Sources/App/Preferences/Keys/`. The `PreferenceKey` type and the
  `TextualUserDefaults` store live in `Sources/Shared/Preferences/`, and only
  the app compiles them; the XPC connection host reads no preferences. Read
  and write through the key, never through a raw defaults string. Defaults
  registration, storage routing, and import/export filtering are derived directly from those declarations;
  do not add a generated plist mirror or a build phase for them.
- The channel transcript is native. `LogRenderer` produces semantic
  `TranscriptLine` values and the transcript adapter draws them with TextKit;
  no HTML, CSS, JavaScript, WebKit, template engine or script bridge belongs in
  this path. `TranscriptTheme` is the single versioned `Codable` appearance
  model. Store and import/export it as an XML property list, and add colours as
  semantic light/dark roles instead of view-specific styling hooks. Inline
  images are decoded natively and fetched only over HTTP(S) with bounded input.
- `@objc` marks a runtime boundary and nothing else: a class or action a nib
  binds, a KVO-observed property, an XPC protocol member, or a plugin
  principal class. A Swift-to-Swift call never needs one.
- Keep external wire, template, persistence and plugin strings at typed
  boundary adapters rather than scattering literals through logic.
- User-facing text lives in feature-namespaced String Catalogs, consumed
  through the generated typed symbols. Preserve translations, placeholders,
  translator comments and attribution; merge two keys only when their meaning
  and formatting contract are identical.

## Targets

`project.yml` declares every target; the tree mirrors it.

| Target | Sources | Kind | Default isolation |
| --- | --- | --- | --- |
| `Glasstual` | `Sources/App/**`, `Sources/Shared/**` | app | `MainActor` |
| `Caffeine`, `ChatFilter`, `SmileyConverter`, `SystemProfiler`, `UserInsights`, `ZNCAdditions` | `Sources/Plugins/<Directory>/**`, where the directory is the target name with spaces: `Chat Filter`, `Smiley Converter`, `System Profiler`, `User Insights`, `ZNC Additions` | first-party plugin bundles | `MainActor` |
| `CocoaExtensions` | `Sources/Frameworks/Cocoa Extensions/**` | framework (Foundation/AppKit helpers) | `nonisolated` |
| `GlasstualPluginKit` | `Sources/Frameworks/Plugin Kit/**` | framework (plugin ABI: `Sendable` event payloads, `@MainActor` callbacks) | `nonisolated` |
| `IRCConnectionHost` | `Sources/Services/IRC Connection Host/**` | capability-limited XPC network host; its exported shim forwards to `ConnectionHost`, which owns sockets and the `Sendable` client proxy | `nonisolated` |
| `GlasstualTests` | `Tests/GlasstualTests/**` and three `Chat Filter` plugin sources with their two String Catalogs; the `IRCSpec` and `TLS` corpora ship as bundle resources, and the `History` fixture test reads its corpus from the source tree | Swift Testing bundle hosted by the app | `MainActor` |
| `GlasstualE2ETests` | `Tests/GlasstualE2ETests/**` | Swift Testing bundle hosted by the test runner, not the app | `MainActor` |
| `GlasstualE2EHarness` | `Tests/E2EHarness/**` | external Accessibility driver, watchdog and loopback peers | `MainActor` |

`Sources/Shared/` holds the declarations the network host shares with the app
(XPC protocols and connection envelopes) and the app's preference store. The
app compiles all of it. The `IRCConnectionHost` target lists the few files it
compiles, and only those cross the process boundary. First-party plugin
preference names live in `Sources/Plugins/Shared/FirstPartyPluginPreferences.swift`.
The app, `Caffeine`, `ChatFilter`, `SmileyConverter` and `SystemProfiler`
compile it.

## Isolation rules

Every piece of mutable state belongs to exactly one isolation domain — the main
actor, a named actor, or a value that never escapes — and the compiler has to
be able to prove it. SwiftLint custom rules enforce the source-level bans below
on every `make lint`.

- **Never add** `nonisolated(unsafe)`, `@unchecked Sendable`,
  `MainActor.assumeIsolated`, `Thread.isMainThread` or
  `DispatchQueue.main.sync`. Each one asserts something the checker cannot see
  and nothing re-checks. When one of them would settle an isolation error, the
  boundary is in the wrong place: move the state into the domain that uses it,
  or hand a `Sendable` snapshot across. None are left in the tree.
- **Never add** an `NSLock`, `NSRecursiveLock`, `objc_sync_enter`, a private
  `DispatchQueue(label:)`, an `OperationQueue()`, or a
  `perform{A,}synchronouslyOnMainQueue` hop. `Mutex<Value>` is the only
  permitted lock, and only around a value type — never around a reference, and
  never held across I/O or an `await`. There is no exemption and no marker that
  buys one: a new queue means the state it guards belongs in an actor, and an
  Apple API that insists on a queue is answered by the bullet below.
- **Where an Apple API forces a bridge, route around the API.** A nonisolated
  AppKit callback is answered from a `Sendable` snapshot the main actor keeps
  current; `sink` and KVO handlers become `for await` loops in a main-actor
  `Task` the owner cancels; a non-`Sendable` connection is created inside the
  actor that owns it so it never crosses a boundary at all.
- **A plain `nonisolated` is a claim, so it has to say which claim.** Write the
  reason as a trailing comment in a closed vocabulary:

  | Marker | Means |
  | --- | --- |
  | `// nonisolated: pure` | a pure function of `Sendable` inputs |
  | `// nonisolated: let` | a `let` of `Sendable` type |
  | `// nonisolated: xpc-shim` | an XPC/`@objc` protocol requirement, or its one-line forwarding shim |
  | `// nonisolated: value` | a `struct`/`enum` with no reference-typed state |
  | `// nonisolated: immutable` | a `final class` with no stored state, or whose every stored property is a `let` of `Sendable` type, a `let Mutex<Value>` included |
  | `// nonisolated: guarded` | a class a boundary pins outside every actor that also holds mutable state, and keeps it safe behind a `Mutex<Value>` or a store that synchronizes itself |

  Nothing else counts as marked. `value` says the type is one, so it never
  belongs on a `class`: a namespace of `static` members becomes an `enum`, and
  a class that only holds `let`s is `immutable`. Owning a `Mutex` as a `let` is
  still `immutable`, which is why `ConnectionInputBudget`,
  `NativeInlineImageTransfer` and `TranscriptHighlightExpressions` carry that
  marker. What moves a class to `guarded` is a stored `var`: `PluginManager`
  and `SmileyConverterPlugin` each keep main-actor state beside the `Mutex` the
  transcript renderer reads off the main actor, and `TextualUserDefaults` is a
  handle on a suite Foundation synchronizes. Those are the three `guarded`
  types. If a site fits none of the six, it is not a `nonisolated` site: a
  nonisolated class with mutable state becomes an actor or a main-actor class.

Four SwiftLint custom rules cover these categories over `Sources/` and `Tests/`
alike, and fail when they find any: `isolation_escape_hatch`,
`manual_lock_or_queue`, `unmarked_nonisolated` and `value_marker_on_class`. A
test helper is a `nonisolated` site like any other and carries the same marker.
All four are at zero and stay there: there is no ceiling to raise, no
ratchet, and no exception to add. A change that trips the gate has put a
boundary in the wrong place — move the state into the domain that uses it, or
hand a `Sendable` snapshot across.

Two runtime checks back the static ones, both local-only because they are far
too slow for CI: `make tsan` runs the suite under ThreadSanitizer, and
`make smoke` launches the Debug app against a copy of the real preferences
with `autoConnect` cleared and a per-run scratch directory in place of the
group container, probes the main thread from outside the process every ten
seconds, and reads the unified log back. The probe is what catches a
blocked main actor — the process stays alive and looks idle, but stops
answering the accessibility API. Tests assert isolation with `expectMainActor()`
and `IsolationProbe` from `Tests/GlasstualTests/Support/`.

## Working in the tree

- `project.yml` is the source of truth for targets, schemes, build settings,
  generated Info.plists, signing, capabilities and entitlements. Sources are
  globbed from directories, so run `make generate` after adding or removing a
  file and commit the regenerated `Glasstual.xcodeproj`. `Glasstual.xcodeproj`
  and `Generated/Xcode/` are never edited by hand.
- Preserve every upstream copyright notice, license, acknowledgement and
  provenance record when moving or rewriting code. Vendored source stays under
  `Sources/Frameworks/Cocoa Extensions/` with
  `Sources/Frameworks/PROVENANCE.md` current.
- SwiftFormat and SwiftLint run over all of `Sources/` and `Tests/`. Fix
  findings in the source, or tune a rule once in `.swiftlint.yml` /
  `.swiftformat` with a repository-wide reason. Path exclusions, baselines,
  inline disables and blanket suppressions stay out of the tree.
- New tests use Swift Testing (`@Test`, `#expect`, `#require`) in
  `Tests/GlasstualTests/`, named after their subject. Test what the code
  decides, not what the compiler already guarantees: a runtime-name pin earns
  its place only where a nib or a protocol constant depends on it.
- A test that does not run is not a passing test. SwiftLint bans `.disabled(…)`
  and `withKnownIssue` under `Tests/`; fix the code or delete the test.
- Before handing off: `make generate`, `make build`, `make test`,
  `make e2e-fixtures` and `make lint`, all green. Report any runtime, signing,
  network or release boundary the change touched but the checks did not
  exercise.
- Commits carry no AI attribution: no `Co-Authored-By` trailer, no generated-by
  note.

## Agent skills

Skills installed for this checkout live under `.agents/skills/` (read by
Codex and OpenCode; `.claude/skills/` symlinks them for Claude Code), pinned in
`skills-lock.json`. They are general Apple-platform guidance, and this file
overrides them wherever the two disagree. The known disagreements:

- `@unchecked Sendable`, `nonisolated(unsafe)`, `MainActor.assumeIsolated`,
  GCD queues and locks other than `Mutex<Value>` are offered as last resorts in
  `write-swift` and `swift-concurrency-pro`. Here they are banned outright; see
  "Isolation rules".
- `#available` gating with fallbacks (`swiftui-expert-skill`) does not apply:
  the deployment target is macOS 26, so an API from 26 or earlier is used
  directly.
- `withKnownIssue` and `.disabled(…)` (`write-swift`) are banned under `Tests/`.
- XCTest for UI automation does not apply: end-to-end coverage goes through the
  Accessibility harness in `Tests/E2EHarness/`.
- WebKit, iOS-only patterns and cross-platform fallbacks do not belong in this
  macOS-only, native-transcript app.
- `xcode-build-fixer` and `xcode-project-analyzer` edit or read
  `project.pbxproj` settings. Here a build setting changes in `project.yml`,
  followed by `make generate`; never edit `Glasstual.xcodeproj` by hand.
- `xcode-compilation-analyzer` injects slow-type-checking warnings, which
  `SWIFT_TREAT_WARNINGS_AS_ERRORS` turns into build failures. Pass
  `SWIFT_TREAT_WARNINGS_AS_ERRORS=NO` for that run only. Point the build
  benchmark scripts at `build/` for output and DerivedData.
- `axiom-performance`, `axiom-networking`, `axiom-security` and
  `swift-security-expert` include GCD timers, atomics, `@unchecked Sendable`
  mocks, XCUITest launch tests and API snippets that do not compile. Use them
  for diagnosis and Apple facts, and check code against the SDK. The
  "always use the data protection keychain" advice must not strand existing
  keychain items: migrate them.
- The Core Data history store keeps automatic migration off on purpose.
- The web quality skills apply to `.github/website/`. GitHub Pages cannot set
  response headers, so ignore header findings such as CSP and HSTS.
