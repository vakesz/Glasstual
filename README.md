<p align="center">
  <img src="Documentation/Images/AppIcon.png" width="160" alt="Glasstual app icon">
</p>

<h1 align="center">Glasstual</h1>

<p align="center">
  A highly customizable IRC client for macOS 26 and later.
</p>

Glasstual is a highly customizable app for interacting with Internet Relay Chat (IRC) chatrooms on macOS.

Glasstual can be customized with styles written in CSS, HTML, and JavaScript; plugins written in Objective-C & Swift; and scripts written in AppleScript (plus many other languages).

## Features

### Chat styles

Two styles ship with the app and are picked in Settings › Style. **Lines** is the classic layout: one line per message with a nickname column and timestamps, set in the system font and colours. **Bubbles** lays the conversation out like Messages: your own messages on the right in the accent colour, everyone else's on the left in a grey bubble, messages from the same person grouped together, and joins, parts and other events as small centred captions. Both follow light and dark mode, the accent colour and the accessibility settings, and both show replies and reactions. Existing installations keep Lines.

## Relationship to Textual

**Glasstual is a fork and continuation of [Textual](https://github.com/Codeux-Software/Textual)**, the IRC client by Codeux Software, LLC. Upstream Textual is no longer actively maintained — it had a single full-time maintainer for the life of the project, who has since moved on. Everyone who contributed to Textual in any form, be it a suggestion, bug report, pull request, financial support, or anything else, made this codebase what it is.

This fork exists to carry that work forward on **macOS 26 (Tahoe) and later**. It is an independent project: it is not published, endorsed, or supported by Codeux Software, LLC, and it does not offer, replace, or update Codeux's builds of Textual.

Copyright and license notices from Textual and LimeChat are left intact throughout the source tree, including the BSD non-endorsement clause naming Textual. Those notices cover code this project did not write and are deliberately unchanged. See [Licenses](#licenses) below and [Acknowledgements.pdf](Documentation/Acknowledgements.pdf).

## Screenshots

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Documentation/Screenshots/main-window-dark.png">
  <img src="Documentation/Screenshots/main-window-light.png" alt="The Glasstual main window connected to the local Harbor IRC demo network, showing channels, a conversation and the member list">
</picture>

<details>
<summary>First launch</summary>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Documentation/Screenshots/welcome-dark.png">
  <img src="Documentation/Screenshots/welcome-light.png" alt="The Glasstual first-launch welcome screen">
</picture>

</details>

The conversation shown above was generated on a loopback-only demo network. It does not contain real accounts or messages.

## Note Regarding Third-Party Frameworks

The Codeux framework Glasstual builds on (Cocoa Extensions) and the prebuilt static libraries live in `Frameworks/` as vendored sources, not submodules. `Frameworks/PROVENANCE.md` records the upstream commit each one was taken from. A plain clone is enough:

```
git clone https://github.com/vakesz/Glasstual.git
```

## Note Regarding Code Signing

**DO NOT change the Code Signing settings through Xcode.** `Glasstual.xcodeproj` is generated from `project.yml` and any change made in the target editor is lost on the next `xcodegen generate`.

**DO** edit `CODE_SIGN_IDENTITY`, `DEVELOPMENT_TEAM`, and related keys in [`project.yml`](project.yml) (`settings.base`). Target Info.plist contents and sandbox entitlements are declared there too; `xcodegen generate` writes those files beside their targets.

**It is HIGHLY DISCOURAGED to turn off code signing.** Certain features rely on the fact that Glasstual is properly signed and is within a sandboxed environment.

**GLASSTUAL DOES NOT REQUIRE A CERTIFICATE ISSUED BY APPLE TO BUILD** which means there is absolutely no reason to turn code signing off.

## Building Glasstual

Glasstual requires Xcode 26 or later on macOS 26 (Tahoe) or later, an Apple Silicon Mac (builds are arm64 only), and a valid code signing certificate (it does not need to be issued by Apple).

This tree has **no paid-license or trial checks**. Precompiled store builds of Textual from codeux.com are a separate product.

1. Install the development tools: `brew bundle` (this includes XcodeGen).
2. Set your Apple Developer **Team ID** as `DEVELOPMENT_TEAM` in [`project.yml`](project.yml) and, if you are not building the official fork, `GLASSTUAL_BUNDLE_IDENTIFIER` there too. The defaults are:
   - Bundle ID: `com.vakesz.glasstual`
   - Team ID: `H8W5DK3FN2`
   - App Group: `group.<Team ID>.<Bundle ID>`

   Register that App ID and App Group on [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list).
3. Regenerate the project if you changed `project.yml` or added files: `make generate`. The generated `Glasstual.xcodeproj` is committed, so a plain checkout builds without XcodeGen.
4. Open `Glasstual.xcodeproj` and build the `Glasstual` scheme, or from the command line:

   ```sh
   make build            # Debug
   make release          # Release
   make run              # build and launch
   ```

   `make help` lists every target; they call `xcodebuild` and the repository tools directly.

   Run and Profile use the `Debug` configuration; Archive uses `Release`. Versions, target Info.plist files, entitlements, schemes, and build settings are declared in `project.yml`.

### Code quality

Install the development tools and run the repository-wide checks with:

```sh
make setup    # brew bundle
make test     # unit tests (GlasstualTests, run inside the Debug app)
make lint     # SwiftLint, SwiftFormat, shellcheck, actionlint and resource validation
make format   # clang-format, SwiftFormat, shfmt
```

The unit tests live in `Tests/GlasstualTests` and do not use the network.

Formatting and linting intentionally exclude the vendored frameworks under
`Frameworks/` and `External Libraries`. `make lint` installs SwiftFormat or
SwiftLint with Homebrew when either executable is missing. The `Quality`
workflow runs the same command on every pull request; `Signed Release`
is run manually from `master` to archive, notarize, attest and publish. Each
GitHub Release includes the notarized ZIP, its SHA-256 checksum and generated
release notes.

### Software Updates

Glasstual has no in-app updater. The Sparkle integration inherited from
Textual was removed together with the upstream appcast so that this fork can
never offer Codeux's builds as an update to itself. New releases are published
on the GitHub releases page.

## Distribution

Glasstual is built to be distributable both as a notarized direct download and
through the Mac App Store from the same tree:

- Every process is sandboxed, the hardened runtime is on and library
  validation is **not** disabled. Plugins therefore load only when signed with
  the same Team ID as the app.
- Off-the-Record (OTR) messaging was removed on 2026-08-22. It depended on
  libotr, libgcrypt and libgpg-error, which are LGPL 2.1 and cannot be
  statically linked into an App Store build. Network traffic is protected by
  TLS instead.
- `ITSAppUsesNonExemptEncryption` is `false`: the app uses only the
  TLS/crypto provided by the operating system, which is exempt from export
  compliance paperwork.
- The direct-download pipeline (`.github/workflows/release.yml`) signs with a
  Developer ID identity. An App Store submission uses the same project with an
  Apple Distribution identity and App Store provisioning profiles (set in
  `project.yml` or on the `xcodebuild` command line).
- Textual and LimeChat are BSD-licensed, so selling builds is permitted as
  long as the notices in [Licenses](#licenses) and `Acknowledgements.pdf`
  ship inside the app (they do: Help ▸ Acknowledgements) and the names
  Textual and Codeux Software are not used to promote the product.

## Supported IRC features

IRCv3 capabilities Glasstual negotiates when the server offers them:

- `account-notify`, `account-tag` and `extended-join` (the services account of each user is tracked and shown in the member list info popover)
- `away-notify`
- `batch` (including nested batches)
- `cap-notify`
- `chathistory` (and `draft/chathistory`): `LATEST` on join fetches what the local scrollback is missing, `BEFORE` fills in above the scrollback when scrolling up runs out of local history; replayed lines are de-duplicated by `msgid`; `/chathistory <subcommand> ...` passes a request through
- `chghost`
- `echo-message` (can be switched off in Preferences)
- `extended-monitor` (away and account changes for monitored nicknames)
- `invite-notify` (invites for other users are shown in the channel)
- `labeled-response` (with `echo-message`, each outgoing `PRIVMSG`/`NOTICE` is labelled and its line shown as pending until the echo, an `ACK`/`BATCH` or a `FAIL` resolves it; styles react through `Glasstual.lineDeliveryStateChanged` and the `data-delivery-state` attribute)
- `message-tags` (incoming and outgoing tags, `TAGMSG`; `msgid` is stored with each line and exposed to styles as `data-msgid`; the `bot` tag marks the sender as a bot)
- `+typing` (client tag on `TAGMSG`): who is typing is shown above the input field, and what you type is reported to the channel or query (`active` at most every three seconds, `paused` after five seconds idle, `done` on send or clear; never for commands or the server console; can be switched off in Settings › Behavior)
- `+draft/reply` (client tag): Reply in a message's context menu quotes that message above the input field and tags what you send; a reply is shown as a quote above the line that clicking scrolls to
- `+draft/react` (client tag on `TAGMSG`): React in a message's context menu sends an emoji; reactions are shown as a row of pills under the line and kept for the session
- `multi-prefix`
- `pre-away` (an away message in effect when a connection dropped is restored before registration completes on reconnect)
- `read-marker` (and `draft/read-marker`): `MARKREAD` from other clients clears unread counts and moves the scrollback mark; viewing a channel tells the bouncer it is read
- `sasl` (`SCRAM-SHA-256`, `PLAIN` and `EXTERNAL`; `SCRAM-SHA-256` is preferred, and `RPL_SASLMECHS` retries with the next mechanism)
- `server-time`
- `setname` (incoming `SETNAME` and the `/setname` command)
- `standard-replies` (`FAIL`, `WARN`, `NOTE`)
- `sts` (Strict Transport Security: a per-host policy is stored, forces TLS on the policy port on later connects, and a plaintext connection is upgraded immediately; policies never downgrade and are excluded from preference export)
- `userhost-in-names`
- ZNC: `znc.in/playback`, `znc.in/self-message`, `znc.in/server-time`, `znc.in/server-time-iso`, `znc.in/tlsinfo`

When the server advertises `WHOX`, channel `WHO` requests use `WHO <channel> %tcuhnfar,152` so the initial member list carries accounts, real names and bot flags. `netsplit` and `netjoin` batches are collapsed into one summary line per channel instead of a QUIT or JOIN per user (hidden along with joins and quits when those are switched off). The `account` tag is parsed into each message. `CAP LS 302` and `CAP NEW`/`CAP DEL` are supported. The capability table lives in `Sources/App/Classes/IRC/IRCCapability.m`.

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

Unless stated otherwise by the [Acknowledgements.pdf](Documentation/Acknowledgements.pdf) document, the license presented below shall govern the distribution of and modifications to; the work hosted by this repository.

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
