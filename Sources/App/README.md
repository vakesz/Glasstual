# Application code

Group code by the feature or domain that owns its state. Keep each feature's
views, models, strings and platform adapters together.

## Ownership

| Directory | Owns |
| --- | --- |
| `Application` | Lifecycle, scenes, menus, alerts, URL handling, Shortcuts intents, Focus filter, resources and service composition. |
| `Protocol` | IRC wire parsing, command vocabulary, capability definitions, mode grammar, formatting and transport-security policies. |
| `Chat` | Sessions, conversations, inbound handling, outbound delivery, connection negotiation, history, address book, notifications, local commands, logging, DCC, network catalog and bouncer networks. |
| `SettingsKeys` | Typed settings, storage, validation, registration, repair and reload requests. |
| `Features` | User-facing features and their presentation state. |
| `Controls` | Shared controls, keyboard dispatch, text editing, layout metrics, color math and link permissions. |
| `Localization` | Shared catalogs, typed accessors and text formatting. |
| `Resources` | App icon, documents, scripts and runtime property lists. |

## Dependencies

- `Application` composes features, chat, protocol and shared controls.
- Features use chat and protocol models, typed settings and shared controls.
- `Chat` uses `Protocol`. Protocol grammar and values do not depend on chat
  sessions, conversations or settings. Session-owned handling belongs in
  `Chat/Inbound`, `Chat/Outbound` and `Chat/Connection`. Neither layer names
  concrete types from `Features`.
- Domain code requests UI work through `Chat/Ports`, supplied by `ChatServices`.
  Use a closure for one operation and a protocol for related operations.
- `Controls` has no feature dependencies or feature state.
- `SettingsReload` publishes requests. Each feature handles its own updates.
- App-wide service composition belongs in `Application/AppServices.swift`.
- `Sources/Shared` contains only XPC contract declarations compiled by both
  the app and the IRC connection host. Shared framing and logging belong in
  `Sources/CocoaExtensions`.

## Notable owners

- `Chat/Bouncer`: soju network discovery, one connection per network and the
  sidebar hierarchy.
- `Chat/Session/Config`: persisted server and conversation configuration.
  `Chat/Session/Keychain` stores its secrets.
- `Application/Intents`: Shortcuts actions and entities.
- `Application/FocusFilter`: the Focus filter intent.
- `Features/ScrollbackSearch`: search across stored history and its window.
- `Features/TranscriptLogViewer`: browsing transcript log files.
- `Features/Scripts`: script discovery, execution, installation prompts and
  strings.
- `Features/Transcript`: `Controller` owns line delivery, history loading,
  reactions and redactions; `Rendering` turns lines into semantic
  `TranscriptRow` values; `View` holds the TextKit adapter; `InlineImages` owns
  bounded image fetching and decoding.

## UI

SwiftUI owns layout, navigation, forms, sheets and scenes. The AppKit adapters
listed in [AGENTS.md](../../AGENTS.md) provide native capabilities and list
rendering. Feature models own domain state.

The main window uses a navigation sidebar and a native member-list inspector.
SwiftUI provides the inspector's resize interaction. A typed window setting
stores its width for later presentations and launches.

## Files

- Name a file after its primary type or concern.
- Keep a small type beside its sole collaborator. Give it a separate file
  when it has multiple callers or hides an independently changing concern.
- Aim for files under 500 lines. Split by responsibility, not line count.
- Keep a sheet's model, session and view together until roughly 250 lines,
  then move the view to `<Name>View.swift`.
- Add a subdirectory only for a cohesive subsystem.
- Prefer domain names. Avoid `Support`, `Utilities`, `Helpers`, `Misc`,
  `Policies`, `Types` and `Models` as catch-all filenames.
- Keep feature String Catalogs beside their consumers.
- Keep abstractions that own behavior. Remove wrappers that only rename a call.

Run `make generate` after adding, moving or removing files.
