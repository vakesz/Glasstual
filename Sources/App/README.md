# Application code

Group code by the feature or domain that owns its state. A feature keeps its
views, models, strings and platform adapters together.

## Ownership

| Directory | Owns |
| --- | --- |
| `Application` | Lifecycle, scenes, menus, alerts, URL handling, resources and service composition. |
| `Protocol` | IRC parsing, commands, capabilities, modes, formatting and transport security. |
| `Chat` | Sessions, conversations, history, address book, notifications, local commands, logging, DCC and network catalog. |
| `SettingsKeys` | Typed settings, storage, validation, registration, repair and reload requests. |
| `Features` | User-facing features and their presentation state. |
| `Controls` | Shared controls, keyboard dispatch, text editing, layout metrics, color math and link permissions. |
| `Localization` | Shared catalogs, typed accessors and text formatting. |
| `Resources` | App icon, documents, scripts and runtime property lists. |

## Dependencies

- `Application` composes features, chat, protocol and shared controls.
- Features use chat and protocol models, typed settings and shared controls.
- `Chat` uses `Protocol`. Neither names concrete types from `Features`.
- Domain code requests UI work through `Chat/Ports`, supplied by `ChatServices`.
  Use a closure for one operation and a protocol for related operations.
- `Controls` has no feature dependencies or feature state.
- `SettingsReload` publishes requests. Each feature handles its own updates.
- App-wide service composition belongs in `Application/AppServices.swift`.
- `Sources/Shared` contains only declarations compiled by both the app and
  the IRC connection host.

`Features/Scripts` owns script discovery, execution, installation prompts and strings.
`Localization/DateFormatting` owns shared date parsing and formatting.

`LinkSchemeRules` owns URL permissions; `LinkParser` locates links in text.
`SettingValue` converts property-list values; `SettingsKey` declares and
validates settings; `SettingsKey+Storage` accesses defaults.

## UI

SwiftUI owns layout, navigation, forms, sheets and scenes. The AppKit adapters
listed in [AGENTS.md](../../AGENTS.md) provide native capabilities and list
rendering. Adapters own native views and interaction state. Feature models own
domain state.

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
- Keep behaviorful abstractions. Remove wrappers that only rename a call.

Run `make generate` after adding, moving or removing files.
