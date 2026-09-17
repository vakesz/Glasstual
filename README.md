<p align="center">
  <img src=".github/website/assets/app-icon.png" width="160" alt="Glasstual app icon">
</p>

<h1 align="center">Glasstual</h1>

<p align="center">
  A native IRC client for macOS 26 and later.
</p>

Glasstual is an Apple Silicon IRC client written in Swift 6. Its interface is
SwiftUI-first, its transcript is rendered natively, and its network connection
runs in a sandboxed XPC host.

## Features

- IRCv3 support, including SASL, server-time, typing notifications, replies,
  reactions, read markers, labeled responses and chat history.
- Native Lines and Bubbles transcript themes with light and dark appearances.
- Multiple servers, channel and member management, notifications, file
  transfers, local scrollback and transcript logging.
- Message rules and user command scripts.
- Strict concurrency checking and typed preferences throughout the app.

## Screenshots

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/website/assets/main-window-dark.png">
  <img src=".github/website/assets/main-window-light.png" alt="The Glasstual main window showing servers, a conversation and the member list">
</picture>

<details>
<summary>First launch</summary>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/website/assets/welcome-dark.png">
  <img src=".github/website/assets/welcome-light.png" alt="The Glasstual first-launch welcome screen">
</picture>

</details>

## Building

Glasstual runs on macOS 26 or later on an Apple Silicon Mac. Building it takes
Xcode 27, the version CI and the release workflow use. The Makefile pins
XcodeGen, SwiftFormat, SwiftLint, actionlint and ShellCheck, and runs each
one through a wrapper under `build/tools/bin`. A pinned version already on
`PATH` is used as it is; otherwise `make` downloads that release, checks its
SHA-256 and unpacks it under `build/tools`.

`project.yml` is the source of truth for targets, build settings, signing,
entitlements and generated metadata. Do not edit target settings or generated
files in `Glasstual.xcodeproj` by hand.

1. Set `DEVELOPMENT_TEAM` in `project.yml`. Change
   `GLASSTUAL_BUNDLE_IDENTIFIER` too when building under another identity.
2. Generate and build the project:

   ```sh
   make generate
   make build
   ```

3. Run the complete checks before submitting a change:

   ```sh
   make test
   make e2e-fixtures
   make lint
   ```

`make help` lists the build, archive, coverage, formatting, smoke-test and
Thread Sanitizer entry points. A valid local signature is recommended because
sandbox groups and XPC embedding depend on signing identity.

## Architecture

Application code is organized by feature under `Sources/App`; the current
ownership and dependency rules are documented in
[`Sources/App/README.md`](Sources/App/README.md). `project.yml` declares the app,
framework, tests and the single IRC connection XPC host.

The source tree is Swift-only. SwiftUI owns user-facing layout and scene
presentation. Small AppKit adapters remain only where a macOS capability has no
complete SwiftUI interface: the main-window responder and restoration shell,
TextKit rich text, a transcript-anchored reaction popover, the dock tile and a
blocking alert used before SwiftUI scenes exist. Those adapters do not own
feature state.

`Cocoa Extensions` is maintained as vendored source. Its exact upstream
revision and preservation requirements are recorded in
[`Sources/CocoaExtensions/PROVENANCE.md`](Sources/CocoaExtensions/PROVENANCE.md).

## Distribution

The app and its XPC host are sandboxed and use the hardened runtime. Library
validation remains enabled, so nothing outside the app's own signature loads
into it. Cryptography is provided by macOS system frameworks. The release
workflow produces a signed and notarized direct-download archive.

Glasstual has no in-app updater. Releases are published through this
repository's GitHub Releases page.

## Relationship to Textual

Glasstual is an independent fork of
[Textual](https://github.com/Codeux-Software/Textual). It is not published,
endorsed or supported by Codeux Software, LLC.

Copyright, license and attribution notices from Textual, LimeChat and vendored
components are preserved in the source and in
[`Acknowledgements.pdf`](Sources/App/Resources/Documentation/Acknowledgements.pdf).

## Licenses

The BSD notices for code originating in LimeChat and Textual are collected in
[`LICENSE`](LICENSE). Additional third-party notices are preserved in
[`Acknowledgements.pdf`](Sources/App/Resources/Documentation/Acknowledgements.pdf)
and alongside vendored source.
