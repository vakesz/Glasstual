# Contributing to Glasstual

Glasstual is an AppKit app written in Objective-C and Swift. It targets
macOS 26 on Apple Silicon only. This page covers the tooling and the
conventions; the [README](README.md) covers what the app does.

## Toolchain

- Xcode 26 or later, with its command line tools selected (`xcode-select`).
- Homebrew, for the helper tools listed in the `Brewfile`:

  ```sh
  make setup
  ```

  This installs XcodeGen, SwiftFormat, SwiftLint, shellcheck, shfmt and
  actionlint. clang-format ships with Xcode.

- A code signing certificate. It does not need to be issued by Apple. Set
  your identity and Team ID in `project.yml` (`CODE_SIGN_IDENTITY`,
  `DEVELOPMENT_TEAM`); do not change signing settings inside Xcode, the
  project file is generated.

## Project layout

| Path | Contents |
| --- | --- |
| `project.yml` | XcodeGen single source of truth for targets, schemes, build settings, signing, Info.plist files, and entitlements. `Glasstual.xcodeproj` is generated from it and committed. |
| `Sources/App/` | The application: `Classes/` / `Modules/` (IRC core, controllers, views, dialogs, preferences), `Resources/` (xibs, strings, plists, styles). |
| `Sources/Shared/` | Code compiled into both the app and the XPC services. |
| `Sources/Plugins/` | Bundled plugins (Caffeine, Chat Filter, Smiley Converter, System Profiler, ZNC Additions). |
| `XPC Services/` | The IRC connection host, the scrollback history store, and the inline media loader. |
| `Frameworks/` | Vendored Codeux frameworks and prebuilt static libraries. `PROVENANCE.md` records their origin. |
| `Tests/GlasstualTests/` | XCTest unit tests for the IRC core. |

## Day to day

```sh
make generate          # regenerate the Xcode project after editing project.yml
make build             # Debug build into DerivedData/
make run               # build and launch
make test              # unit tests
make lint              # SwiftLint, SwiftFormat, shellcheck, actionlint and resource validation
make format            # rewrite Objective-C, Swift and shell sources in place
```

`.vscode/` holds recommended extensions and settings that match the
formatters above. Xcode users need nothing extra.

## Conventions

- **Formatting** is mechanical: `.clang-format` for Objective-C and C,
  `.swiftformat` for Swift, `shfmt -i 0 -ci -sr` for shell. Run
  `make format` before committing; CI runs the same checks through `make lint`.
- **Indentation** is tabs in source, two spaces in JSON/YAML/JS/CSS
  (`.editorconfig`).
- **Objective-C** files keep the `NS_ASSUME_NONNULL_BEGIN`/`END` pair, declare
  private properties in a class extension, and mark designated initializers.
  Guard server input with `NSAssertReturn` or a real check, not
  `NSParameterAssert` alone; assertions are off in Release.
- **Swift** uses Swift 6 language mode with strict concurrency. Code that
  must run on the main thread is `@MainActor`.
- **UI** is AppKit. No SwiftUI. Use system semantic colours and SF Symbols;
  present alerts as sheets, not modal panels.
- **User-facing strings** go in `Sources/App/Resources/Language Files/en.lproj/*.strings`
  with a unique `xxx-xx` key and are read through `TXTLS()`.
- **Licence headers** on files that originate from Textual or LimeChat stay
  as they are. New files carry the Glasstual header.
- **Commits** describe the change in the imperative mood and explain why
  when it is not obvious. Do not add `Co-Authored-By` or other trailers.

## Adding things

- **A preference**: register the default in
  `RegisteredUserDefaultsInContainer.plist`, list the key in
  `PreferenceKeyMasterList.plist`, add an accessor in
  `TPCPreferencesLocal`, and exclude it from export in
  `KeysExcludedFromExport.plist` if it is machine specific.
- **An IRC command**: add it to `IRCCommandIndexLocalData.plist` (or the
  remote data plist for commands received from the server), the matching
  enum in `IRCCommandIndex.h`, and the handler in `IRCClient.m`.
- **An IRCv3 capability**: add an entry to the capability registry in
  `IRCClient.m` and, if the server sends new commands for it, a remote
  command as above.
- **A style**: styles are HTML/CSS/JavaScript bundles under
  `Sources/App/Resources/Styles/`. The JavaScript API the app exposes lives in
  `Sources/App/Resources/Styling/JavaScript/API/`.
- **A plugin**: plugins are `.bundle` targets in `Sources/Plugins/` loaded
  through `THOPluginManager`. Library validation is on (a Mac App Store
  requirement), so a plugin loads only if it is signed with the same Team ID
  as the app; the app still asks the user once before loading a bundle from
  outside the application bundle.

## Reporting problems

Open an issue at <https://github.com/vakesz/Glasstual/issues>. The
templates ask for the Glasstual and macOS versions and the network you were
connected to, which is usually what is needed to reproduce an IRC problem.
