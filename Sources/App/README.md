# Application architecture

`Sources/App` contains the `Glasstual` application target. Code is grouped by
the domain that owns its state and behavior, not by framework type or by a
former class name.

## Ownership

| Directory | Responsibility |
| --- | --- |
| `Application/` | Process lifecycle, SwiftUI scenes, URL handling, appearance, paths, resources and application-wide coordination. `Application/Alerts` owns the alert request, the system presenter, the suppression store and the certificate trust panel; `Application/Menus` owns the programmatic `NSMenu` command graph and its action controller. |
| `Protocol/` | The IRC protocol itself: wire parsing and writing, inbound handlers and numerics, outbound commands, capability negotiation, modes, formatting control codes and transport security. |
| `Chat/` | The chat domain built on that protocol: the server session and its conversations (`Session`), the ports the domain calls the user interface through (`Ports`), connection lifecycle, history and the `Scrollback` database, the address book, the notification seam, local commands, transcript file logging, direct connections (DCC) and the network catalog. |
| `SettingsKeys/` | Typed settings declarations — one file per key domain — plus the defaults store, the app group, and the launch-time registration, repair and reload steps. `SettingsReload` maps a changed key to what the application has to redo and announces it as a `SettingsReloadRequest`; each owner of live state answers the obligations that are its own, so nothing here reaches into a feature. |
| `Features/` | User-facing behavior. Each feature owns its views, presentation model, validation, strings and feature-specific platform adapters. |
| `Controls/` | Reusable controls and platform adapters with no single feature owner: spacing and metrics, colour math, reduce-motion, the formatted text view, sheet chrome, the submission gate, form validation labels, the network picker list and link opening. It owns no feature state and names no feature. |
| `Services/` | Application services that are neither UI nor protocol. Today that is `Services/Scripts`, the user-script catalog and runner. |
| `Localization/` | Hand-written accessors over the generated String Catalog symbols, the application-wide catalogs (`Accessibility`, `Application`, `CommonErrors`, `ConnectionSafety`, `NetworkPicker`, `Prompts`) and shared formatting or validation text. |
| `Resources/` | The `AppIcon.icon` app icon, documents and the few property lists and scripts loaded at runtime. String Catalogs live beside the code that reads them. |

The features are `MainWindow`, `Transcript`, `Sidebar`, `MemberList`,
`ServerProperties`, `ChannelProperties`, `ServerChannelList`, `AddressBook`,
`ChannelSpotlight`, `FileTransfer`, `HighlightLog`, `Notifications`,
`Onboarding`, `Rules`, `Settings`, `SettingsTransfer` and `About`. A feature may
have subdirectories when a cohesive subsystem benefits from a separate boundary;
for example `MainWindow/Input` owns the TextKit input stack and
`Transcript/Theme` owns the versioned appearance model and its store.

## Dependency direction

- Application composition may depend on features, the chat domain, protocol
  code and shared controls.
- Features may depend on the chat domain, protocol models, settings keys and
  shared controls.
- `Chat/` may depend on `Protocol/`; neither depends on `Features/`. Where the
  domain needs something a feature does, it declares a port — a protocol where
  several questions travel together, a closure where there is one — and the
  feature conforms to it or supplies it. The protocol ports live together in
  `Chat/Ports` and are named `…Presenting` (`ServerSessionPresenting`,
  `ChatSessionPresenting`, `ChatItemPresenting`, `MenuPresenting`,
  `ChannelListPresenting`, `ApplicationStatePresenting`,
  `UserNotificationPresenting`, `FileTransferPresenting`), except the two that
  ask rather than present (`MessageRuleFiltering`, `UserScriptRunning`). Every such port is a
  member of `ChatServices`, so domain code never names `AppServices` or any
  other type under `Application/`. No file under `Protocol/` or `Chat/` names a
  type declared under `Features/`, with no exceptions.
- A value the domain fills in lives with the domain; the rule that decides how
  it is delivered lives with the feature that delivers it. Split a type that
  does both at that line. The notification family is the worked example:
  `Chat/Notifications` declares what happened and whether it is worth raising
  (`UserNotificationEvent`, `UserNotificationPayload`,
  `UserNotificationAdmissionContext`, `UserNotificationPolicy`,
  `PendingUserNotification`, `UserNotificationContent`), and
  `Features/Notifications` owns delivery alone — the `UNUserNotificationCenter`
  delegate, the permission prompt, the categories and actions, banner and burst
  behaviour and the alert sound.
- A `static var` or `static let` that names a live object is installed by
  `Application/` and read through a port everywhere else. `AppServices` is the
  composition root and the one place allowed to hold them; a lower layer that
  needs one takes it as a `ChatServices` member (`notifications`,
  `fileTransfers`, `messageRules`, `scripts`, `themeNicknameFormat`,
  `updateDockBadge`) or as an injected value (`stsPolicies`).
- `Controls/` names no feature at all, not even the main window. The window a
  shared alert hangs its sheet from arrives as an `NSWindow` that `Application/`
  installs (`SheetPresentation`); the state-driven sheet chain, and the base
  class a feature's sheet subclasses, belong to `Features/MainWindow`.
- Cross-process declarations belong in `Sources/Shared`, which holds only what
  both the app and the connection host compile, so both targets glob the folder.
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
drag-and-drop, accessibility and restoration before removing it. Do not
reproduce an AppKit control in SwiftUI when the system already provides a native
SwiftUI scene or modifier.

## Naming and files

- Name a Swift file after its primary type.
- Use domain names without historical prefixes.
- A type gets a file of its own when it is roughly 80 lines or more, or when
  two or more other production files use it. A smaller type with one
  collaborator lives in that collaborator's file. Keep files under roughly 500
  lines, and do not name one `Support`, `Utilities`, `Helpers`, `Misc`,
  `Policies`, `Types` or `Models`.
- Keep a sheet feature in one file — its model, its session and its view —
  until that file passes roughly 250 lines, then split the view out as
  `<Name>View.swift`.
- Use `@objc` only for a runtime boundary such as XPC, KVO or a selector.
  Preserve an existing Objective-C runtime name when a persisted archive or
  external contract depends on it.
- Put feature strings in a feature-namespaced String Catalog. Shared strings
  belong in `Localization/`.
- Keep wire and persistence string constants at their boundary adapter.
- Add a subdirectory only when it gives a cohesive subsystem a clear owner.

`project.yml` globs the application directories. Run `make generate` after
adding, moving or removing source files; never edit the generated Xcode project
by hand.
