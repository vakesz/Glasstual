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
  instead. Where one is unavoidable, mark it `ISOLATION-EXCEPTION:` with the
  reason, as the existing ones are.
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
