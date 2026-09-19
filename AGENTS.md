# Repository guidance

Glasstual is an arm64 macOS 26+ IRC client written in Swift 6 with complete
strict concurrency and main-actor default isolation. The source tree is
Swift-only.

## Architecture

- SwiftUI owns layout, navigation, forms, sheets and scene presentation.
  AppKit adapters provide platform capabilities and the approved native list
  rendering below. Keep domain state in the feature model; adapters own only
  native view, reuse and interaction state.
- Preserve keyboard commands, focus, selection, drag and drop, accessibility
  and restoration when changing an adapter. The deliberate adapters are the
  main-window responder and restoration shell, programmatic `NSMenu` command
  graph, TextKit input and transcript views, transcript reaction popover,
  the sidebar outline and member/channel tables, dock-tile renderer and
  pre-scene blocking alerts.
- Organize app code by feature under `Sources/App`. A feature owns its views,
  models, controllers, strings and capability adapters. Read
  `Sources/App/README.md` when moving or adding app files.
- Give a file the name of its primary type or concern. Keep closely coupled
  behavior together; split only at a boundary that hides meaningful
  complexity or changes independently.
- Model closed state with enums, option sets and value types. Use `Codable`
  for persistence. Use `NSSecureCoding` only at an XPC allowlist or an
  existing archived runtime boundary.
- Keep wire, persistence, notification and system identifiers at typed
  boundary adapters. Avoid raw defaults keys and duplicated protocol strings.
- `@objc` marks a KVO, selector or XPC runtime boundary. Swift-to-Swift
  calls stay native.

## Isolation

Every mutable value belongs to the main actor, a named actor, or a value that
does not escape. Move state to its owner or pass a `Sendable` snapshot when
the compiler cannot prove that boundary.

- Keep `@unchecked Sendable`, `nonisolated(unsafe)`,
  `MainActor.assumeIsolated`, `Thread.isMainThread` and
  `DispatchQueue.main.sync` out of the tree.
- Use actors for mutable asynchronous state. `Mutex<Value>` is the only
  permitted lock, only around a value type, and never across I/O or `await`.
  Keep `NSLock`, `NSRecursiveLock`, `objc_sync_enter`, private dispatch
  queues, private operation queues and synchronous main-queue hops out.
- When an Apple API forces a nonisolated callback, answer from a `Sendable`
  snapshot maintained by the owning actor. Replace sink and KVO callbacks with
  an owned `for await` task when an async sequence is available. Construct a
  non-`Sendable` connection inside its owning actor.
- A plain `nonisolated` class, actor, function or variable carries one
  trailing reason marker. Value types and `Sendable` constants need no
  restatement.

  | Marker | Meaning |
  | --- | --- |
  | `// nonisolated: pure` | Pure behavior over `Sendable` inputs or immutable state |
  | `// nonisolated: xpc-shim` | XPC or `@objc` protocol requirement and its forwarding shim |
  | `// nonisolated: immutable` | Final class with only `let Sendable` state, including a `let Mutex<Value>` |
  | `// nonisolated: guarded` | Boundary class with mutable state protected by `Mutex<Value>` or a synchronizing store |

The four isolation rules in `.swiftlint.yml` stay at zero. A finding means
the boundary must move; it does not justify an exclusion or suppression.

## Settings, transcript and localization

- Declare typed `SettingsKey` values under `Sources/App/SettingsKeys`, which
  also holds the defaults store and the launch-time registration, repair and
  reload steps. Read and write through those declarations. Registration, storage
  routing and import/export filtering derive from the declarations, with no
  generated plist mirror.
- `Sources/Shared` contains the XPC declarations and nothing else, so both the
  app and the connection host compile the whole folder. The connection host
  reads no settings.
- `TranscriptRenderer` produces semantic `TranscriptRow` values and the
  TextKit adapter draws them. Keep HTML, CSS, JavaScript, WebKit and script
  bridges out of the transcript.
- `TranscriptTheme` is the versioned `Codable` appearance model. Store and
  exchange it as an XML property list. Add colors as semantic light/dark roles.
- Fetch inline images only over HTTP(S), with bounded download and decode
  inputs.
- Put user-facing text in feature-namespaced String Catalogs and use generated
  typed symbols. Preserve translations, placeholders, translator comments and
  attribution. Merge keys only when meaning and formatting contracts match.

## Repository work

- Treat `project.yml` as the source of truth. Run `make generate` after
  adding or removing files or changing build metadata. Generated
  `Glasstual.xcodeproj` and `Generated/Xcode` files stay untracked and
  unedited.
- Preserve copyright, license, acknowledgement and provenance records.
  Vendored Cocoa Extensions stay under `Sources/CocoaExtensions`; keep their
  full upstream headers and `PROVENANCE.md` current.
- Fix formatting and lint findings in source. Repository-wide rule changes
  need a repository-wide reason. Keep path exclusions, baselines, inline
  disables and blanket suppressions out.
- Keep unrelated working-tree changes intact. Do not create commits unless the
  user asks for them. Commits contain no AI attribution.

## Tests and completion

- Write new tests with Swift Testing in `Tests/GlasstualTests`, named after
  their subject. Test decisions and runtime contracts, not compiler
  guarantees. Runtime-name tests belong only where an archive, a saved window
  frame, KVO or a protocol constant depends on the name.
- End-to-end coverage uses the Accessibility harness under
  `Tests/E2EHarness`, not XCTest UI automation.
- Every test runs. Fix or remove failures; `.disabled` and `withKnownIssue`
  are lint errors under `Tests`.
- Before handoff, run `make generate`, `make build`, `make test`,
  `make e2e-fixtures` and `make lint`. Report any signing, network,
  runtime or release boundary those checks did not exercise.
- `make tsan` and `make smoke` are slow local isolation checks. Run them
  when concurrency changes warrant the cost.

## Local skills

Repository skills provide general Apple guidance; this file wins on conflict.
In particular:

- Concurrency skills may suggest unsafe isolation, GCD queues or locks as last
  resorts. Use the isolation rules above.
- SwiftUI guidance may suggest availability fallbacks. The deployment target
  is macOS 26, so use APIs available in 26 directly.
- Testing guidance may suggest disabled tests, known issues or XCUITest. Use
  the test rules above.
- Xcode optimization skills may edit generated project files. Change
  `project.yml`, then regenerate. Run slow-type-check diagnostics with
  `SWIFT_TREAT_WARNINGS_AS_ERRORS=NO` for that diagnostic run only.
- Networking, performance and security snippets may contain unsupported
  synchronization or unverified APIs. Use them for diagnosis, then check code
  against the SDK and this repository's isolation rules.
- The Core Data history store deliberately keeps automatic migration off.
- Web quality checks apply only to `.github/website`. GitHub Pages cannot set
  response headers, so header-only findings such as CSP and HSTS are out of
  scope.
