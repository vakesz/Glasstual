<p align="center">
  <img src="Documentation/Images/AppIcon.png" width="160" alt="Glasstual app icon">
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
- Bundled Swift plugins and user command scripts.
- Strict concurrency checking and typed preferences throughout the app.

## Screenshots

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Documentation/Screenshots/main-window-dark.png">
  <img src="Documentation/Screenshots/main-window-light.png" alt="The Glasstual main window showing servers, a conversation and the member list">
</picture>

<details>
<summary>First launch</summary>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Documentation/Screenshots/welcome-dark.png">
  <img src="Documentation/Screenshots/welcome-light.png" alt="The Glasstual first-launch welcome screen">
</picture>

</details>

## Building

Glasstual requires macOS 26 or later, an Apple Silicon Mac, Xcode 26 or later,
and XcodeGen. SwiftFormat, SwiftLint, actionlint and ShellCheck are used by the
quality gate.

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
   make lint
   ```

`make help` lists the build, archive, coverage, formatting, smoke-test and
Thread Sanitizer entry points. A valid local signature is recommended because
sandbox groups, XPC embedding and plugin loading depend on signing identity.

## Architecture

Application code is organized by feature under `Sources/App`; the current
ownership and dependency rules are documented in
[`Sources/App/README.md`](Sources/App/README.md). `project.yml` declares the app,
frameworks, plugins, tests and the single IRC connection XPC host.

The source tree is Swift-only. SwiftUI owns user-facing layout and scene
presentation. Small AppKit adapters remain only where a macOS capability has no
complete SwiftUI interface: the main-window responder and restoration shell,
TextKit rich text, a transcript-anchored reaction popover, the dock tile and a
blocking alert used before SwiftUI scenes exist. Those adapters do not own
feature state.

`Cocoa Extensions` is maintained as vendored source. Its exact upstream
revision and preservation requirements are recorded in
[`Sources/Frameworks/PROVENANCE.md`](Sources/Frameworks/PROVENANCE.md).

## Distribution

The app and its XPC host are sandboxed and use the hardened runtime. Library
validation remains enabled, so plugins must be signed with the same Team ID as
the app. Cryptography is provided by macOS system frameworks. The release
workflow produces a signed and notarized direct-download archive; the project
also supports App Store signing profiles.

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

### Original LimeChat License

Textual began as a fork of [LimeChat](https://github.com/psychs/limechat) in 2010, and Glasstual continues from Textual.

LimeChat's original license is presented below.

<pre>
The New BSD License

Copyright (c) 2008 - 2010 Satoshi Nakagawa < psychs AT limechat DOT net >
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
SUCH DAMAGE.
</pre>

### License for content originating from Textual

Unless stated otherwise by the [Acknowledgements.pdf](Sources/App/Resources/Documentation/Acknowledgements.pdf) document, the license presented below shall govern the distribution of and modifications to; the work hosted by this repository.

<pre>
Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
      Please see Acknowledgements.pdf for additional information.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

   * Redistributions of source code must retain the above copyright
     notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above copyright
     notice, this list of conditions and the following disclaimer in the
     documentation and/or other materials provided with the distribution.
   * Neither the name of Textual, "Codeux Software, LLC", nor the
     names of its contributors may be used to endorse or promote products
     derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
SUCH DAMAGE.
</pre>
