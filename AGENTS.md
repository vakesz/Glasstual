# Repository guidance

Glasstual is a macOS 26+ IRC client, arm64 only, written entirely in Swift 6
with `SWIFT_STRICT_CONCURRENCY=complete`. The Objective-C port finished: there
are no `.h`, `.m`, `.c` or `.mm` files left, and none should come back.

## Architecture

- The direction is SwiftUI. New UI is written in SwiftUI and hosted by an
  AppKit shell (`…Sheet.swift` / window controller) that owns presentation,
  validation, menus, keyboard handling, state restoration and the delegate
  callbacks; existing AppKit surfaces migrate feature by feature behind those
  shells. The main window, menu bar, member list and WebKit channel view stay
  AppKit until a migration is planned and measured — never rewrite them as a
  side effect of another change.
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
  `Sources/App/Preferences/Keys/`, with the handful the XPC services
  also read in `Sources/Shared/Preferences/`. Read and write through the key,
  never through a raw defaults string.
- `@objc` marks a runtime boundary and nothing else: a class or action a nib
  binds, a KVO-observed property, an XPC protocol member, or a plugin
  principal class. A Swift-to-Swift call never needs one.
- Keep external wire, template, persistence and plugin strings at typed
  boundary adapters rather than scattering literals through logic.
- User-facing text lives in feature-namespaced String Catalogs, consumed
  through the generated typed symbols. Preserve translations, placeholders,
  translator comments and attribution; merge two keys only when their meaning
  and formatting contract are identical.

## Isolation rules

Every piece of mutable state belongs to exactly one isolation domain — the main
actor, a named actor, or a value that never escapes — and the compiler has to
be able to prove it. The rules below are what `scripts/isolation-gate.sh`
checks on every `make lint`.

- **Never add** `nonisolated(unsafe)`, `@unchecked Sendable`,
  `MainActor.assumeIsolated`, `Thread.isMainThread` or
  `DispatchQueue.main.sync`. Each one asserts something the checker cannot see
  and nothing re-checks. When one of them would settle an isolation error, the
  boundary is in the wrong place: move the state into the domain that uses it,
  or hand a `Sendable` snapshot across. The ones still in the tree carry an
  `ISOLATION-EXCEPTION:` comment and are being removed, not imitated.
- **Never add** an `NSLock`, `NSRecursiveLock`, `objc_sync_enter`, a private
  `DispatchQueue(label:)`, an `OperationQueue()`, or a
  `perform{A,}synchronouslyOnMainQueue` hop. `Mutex<Value>` is the only
  permitted lock, and only around a value type — never around a reference, and
  never held across I/O or an `await`.
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

  Nothing else counts as marked. If a site fits none of the four, it is not a
  `nonisolated` site: a nonisolated class with mutable state becomes an actor,
  a main-actor class, or a `Mutex`-guarded value.

The gate counts three categories under `Sources/` and fails when one rises
above the ceiling recorded in `scripts/isolation-ceilings.env`. The ceilings
only ever fall. After merging work that removes sites, lower them and commit
the result in the same change:

```
make isolation-ratchet   # or: ./scripts/isolation-gate.sh --ratchet
```

Phase 8 finishes when all three read `0`, at which point the ceilings go away
and the gate becomes a flat ban.

Two runtime checks back the static ones, both local-only because they are far
too slow for CI: `make tsan` runs the suite under ThreadSanitizer, and
`make smoke` launches the Debug app against a copy of the real preferences
with `autoConnect` cleared, probes the main thread from outside the process
every ten seconds, and reads the unified log back. The probe is what catches a
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
  `Sources/Frameworks/Static Libraries/` with its `PROVENANCE.md` current.
- SwiftFormat and SwiftLint run over all of `Sources/` and `Tests/`. Fix
  findings in the source, or tune a rule once in `.swiftlint.yml` /
  `.swiftformat` with a repository-wide reason. Path exclusions, baselines,
  inline disables and blanket suppressions stay out of the tree.
- New tests use Swift Testing (`@Test`, `#expect`, `#require`) in
  `Tests/GlasstualTests/`, named after their subject. Test what the code
  decides, not what the compiler already guarantees: a runtime-name pin earns
  its place only where a nib or a protocol constant depends on it.
- Before handing off: `make generate`, `make build`, `make test` and
  `make lint`, all green. Report any runtime, signing, network or release
  boundary the change touched but the checks did not exercise.
- Commits carry no AI attribution: no `Co-Authored-By` trailer, no generated-by
  note.
