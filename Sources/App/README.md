# Application architecture

`Sources/App` contains the `Glasstual` application target. Code is grouped by
the domain that owns its state and behavior, not by framework type or by a
former class name.

## Ownership

| Directory | Responsibility |
| --- | --- |
| `Application/` | Process lifecycle, SwiftUI scenes, app commands, URL handling, appearance, paths, resources and application-wide coordination. |
| `Protocol/` | IRC parsing, negotiation, connection lifecycle, commands, models and presentation decisions. It does not present windows or sheets. |
| `Preferences/` | Typed preference declarations, persistence, import/export, transcript themes and the SwiftUI Settings scene. |
| `Features/` | User-facing behavior. Each feature owns its views, presentation model, validation, strings and feature-specific platform adapters. |
| `UI/` | Small reusable platform adapters and controls with no feature owner. It does not own feature state. |
| `Localization/` | Generated string accessors and shared formatting or validation text. |
| `Resources/` | Asset catalogs, String Catalogs, documents and the few resources loaded at runtime. |

The main features are `MainWindow`, `ChannelView`, `ServerList`, `MemberList`,
`ServerProperties`, `ChannelProperties`, `FileTransfer`, `Notifications`,
`Onboarding`, `Plugins` and `About`. A feature may have subdirectories when a
cohesive subsystem benefits from a separate boundary; for example,
`ChannelView/History` owns the in-process scrollback actor and Core Data model.

## Dependency direction

- Application composition may depend on features, protocol code and shared UI.
- Features may depend on protocol models, preferences and shared UI.
- Protocol code must not depend on feature presentation.
- Shared UI must not import feature-specific state.
- Cross-process declarations belong in `Sources/Shared`, not in the app target.
- The IRC connection host is the only XPC service. Keep its messages as
  `Sendable` values and its exported object as a forwarding shim to its actor.

Prefer a direct feature API over one-method wrappers. A useful boundary hides
state, ordering, validation or a platform contract; it should not merely rename
another call.

## Native UI

SwiftUI owns user-facing layout, navigation, forms and scene presentation.
AppKit is limited to narrow macOS capability adapters: the main-window shell
that provides restoration and responder-chain commands, TextKit-backed input
and transcripts, a transcript-anchored reaction popover, dock-tile rendering
and the blocking alert path used before a SwiftUI scene exists. These adapters
translate platform events and host no business state.

When replacing an adapter, preserve keyboard commands, focus, selection,
drag-and-drop, accessibility, restoration and plugin behavior before removing
it. Do not reproduce an AppKit control in SwiftUI when the system already
provides a native SwiftUI scene or modifier.

## Naming and files

- Name a Swift file after its primary type.
- Use domain names without historical prefixes.
- Use `@objc` only for a runtime boundary such as XPC, KVO, a nib action or a
  plugin principal class. Preserve an existing Objective-C runtime name when a
  persisted archive or external contract depends on it.
- Put feature strings in a feature-namespaced String Catalog. Shared strings
  belong in `Localization/`.
- Keep wire, persistence and plugin string constants at their boundary adapter.
- Add a subdirectory only when it gives a cohesive subsystem a clear owner.

`project.yml` globs the application directories. Run `make generate` after
adding, moving or removing source files; never edit the generated Xcode project
by hand.
