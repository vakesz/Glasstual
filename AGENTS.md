# Repository rules

Glasstual targets arm64 macOS 26+. It uses Swift 6, complete strict concurrency
and main-actor default isolation. All source code is Swift.

## Ownership and UI

- Before adding or moving app files, read [Sources/App/README.md](Sources/App/README.md).
  Group code by feature. Name files after their primary type or concern.
  Keep coupled behavior together; split at an independently changing concern.
- SwiftUI owns layout, navigation, forms, sheets and scenes. Feature models
  own domain state. AppKit adapters own native views, reuse and interaction.
- Keep these AppKit adapters: main-window responder and restoration shell,
  `NSMenu` command graph, TextKit input and transcript, reaction popover,
  sidebar outline, member and channel tables, search-window geometry probe,
  dock tile and blocking alerts before scene creation.
- Adapter changes must preserve keyboard commands, focus, selection, drag and
  drop, accessibility and restoration.
- Model closed state with enums, option sets and value types. Use `Codable`
  for persistence. Reserve `NSSecureCoding` for XPC allowlists and existing
  archived runtime contracts.
- Keep wire, persistence, notification and system identifiers at typed
  adapters. Use `@objc` only for KVO, selectors or XPC. Preserve runtime names
  required by existing contracts.

## Isolation

Every mutable value has one owner: the main actor, a named actor, or a local
value that does not escape. Pass `Sendable` snapshots across isolation boundaries.

- Use actors for mutable asynchronous state. `Mutex<Value>` is the only
  permitted lock, only around a value type, never across I/O or `await`.
- Do not use `@unchecked Sendable`, `nonisolated(unsafe)`,
  `MainActor.assumeIsolated`, `Thread.isMainThread`, `DispatchQueue.main.sync`,
  `NSLock`, `NSRecursiveLock`, `objc_sync_enter`, private dispatch or operation
  queues, or synchronous main-queue hops.
- Answer nonisolated Apple callbacks from snapshots maintained by the owner.
  Prefer owned `for await` tasks to sink or KVO callbacks when an async
  sequence exists. Construct non-`Sendable` connections inside their actor.
- A plain `nonisolated` class, actor, function or variable needs one trailing
  reason marker. Value types and `Sendable` constants do not.

| Marker | Meaning |
| --- | --- |
| `// nonisolated: pure` | Pure behavior over `Sendable` inputs or immutable state. |
| `// nonisolated: xpc-shim` | XPC or `@objc` protocol requirement and forwarding shim. |
| `// nonisolated: immutable` | Final class with only `let Sendable` state, including `let Mutex<Value>`. |
| `// nonisolated: guarded` | Mutable state protected by `Mutex<Value>` or a synchronizing store. |

Keep isolation lint findings at zero. Fix ownership instead of suppressing findings.

## Settings and content

- Declare settings under `Sources/App/SettingsKeys` and access them through
  typed keys. Registration, storage routing and import/export filtering derive
  from declarations. Do not add a generated plist mirror or raw defaults keys.
- `Sources/Shared` contains only XPC declarations. Both targets compile the
  folder. The connection host reads no settings.
- `TranscriptRenderer` produces semantic `TranscriptRow` values for TextKit.
  Keep HTML, CSS, JavaScript, WebKit and script bridges out of the transcript.
- Store the versioned `Codable` `TranscriptTheme` as an XML property list.
  Define colors as semantic light/dark roles.
- Fetch inline images only over HTTP(S), with bounded downloads and decoding.
- Use feature-namespaced String Catalogs and generated symbols for user-facing
  text. Preserve translations, placeholders, translator comments and attribution.
  Merge keys only when meaning and formatting contracts match.
- Keep automatic migration disabled for the Core Data history store.

## Changes and checks

- Edit `project.yml` for build metadata. Run `make generate` after file or
  metadata changes. Keep `Glasstual.xcodeproj` and `Generated/Xcode` untracked
  and unedited.
- Keep build caches, test results and review artifacts outside the checkout.
  Use Xcode defaults, `~/Library/Caches` and `~/Library/Logs`.
- Preserve copyright, licenses, acknowledgements and provenance. Vendored
  Cocoa Extensions stay under `Sources/CocoaExtensions`, with full upstream
  headers and an up-to-date `PROVENANCE.md`.
- Fix formatting and lint in source. Rule changes need a repository-wide
  reason. Do not add path exclusions, baselines, inline disables or blanket
  suppressions.
- Preserve unrelated changes. Commit only when asked, without AI attribution.
- Write new tests with Swift Testing in `Tests/GlasstualTests`, named after
  their subject. Test decisions and runtime contracts. Test runtime names only
  when archives, saved window frames, KVO or protocol constants depend on them.
- Use `Tests/E2EHarness` for Accessibility tests, not XCTest UI automation.
  Every test must run. Fix or remove failures; no `.disabled` or `withKnownIssue`.
- Before handoff, run `make generate`, `make build`, `make test`,
  `make e2e-fixtures` and `make lint`. Report untested signing, network, runtime
  and release boundaries. Run `make tsan` and `make smoke` when concurrency
  changes warrant them.

## Skills

Use repository skills under `.agents/skills`. These rules override conflicting
skill examples. Use macOS 26 APIs directly and verify unfamiliar APIs against
the installed SDK. Change `project.yml`, never generated Xcode files.
For slow-type-check diagnostics only, set `SWIFT_TREAT_WARNINGS_AS_ERRORS=NO`.
Web quality checks apply only to `.github/website`; header-only checks such as
CSP and HSTS are out of scope on GitHub Pages.
