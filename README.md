# Glasstual

Glasstual is a highly customizable app for interacting with Internet Relay Chat (IRC) chatrooms on macOS.

Glasstual can be customized with styles written in CSS, HTML, and JavaScript; plugins written in Objective-C & Swift; and scripts written in AppleScript (plus many other languages).

## Relationship to Textual

**Glasstual is a fork and continuation of [Textual](https://github.com/Codeux-Software/Textual)**, the IRC client by Codeux Software, LLC. Upstream Textual is no longer actively maintained — it had a single full-time maintainer for the life of the project, who has since moved on. Everyone who contributed to Textual in any form, be it a suggestion, bug report, pull request, financial support, or anything else, made this codebase what it is.

This fork exists to carry that work forward on **macOS 26 (Tahoe) and later**. It is an independent project: it is not published, endorsed, or supported by Codeux Software, LLC, and it does not offer, replace, or update Codeux's builds of Textual.

Copyright and license notices from Textual and LimeChat are left intact throughout the source tree, including the BSD non-endorsement clause naming Textual. Those notices cover code this project did not write and are deliberately unchanged. See [Licenses](#licenses) below and [Acknowledgements.pdf](Acknowledgements.pdf).

A number of identifiers keep the Textual spelling on purpose, because they name upstream Textual rather than this app — the sandbox-migration sources in `TPCSandboxMigration.m` and the running-app check in `TXApplication.m`. Renaming those breaks importing data from an existing Textual install.

## Screenshots

<!-- TODO: add screenshots of Glasstual here (light and dark). -->

_Screenshots pending — insert image here._

## Note Regarding Downloading Source Code

Glasstual depends on several other projects to build. This repository is linked against them using submodules — clicking "Download ZIP" will not download a copy of those projects. Clone the source instead:

```
git clone https://github.com/vakesz/Textual.git Glasstual
cd Glasstual
git submodule update --init --recursive
```

## Note Regarding Code Signing

**DO NOT change the Code Signing Identity setting through Xcode.** Glasstual uses a configuration file to specify the code signing identity. This allows it to be used across all projects associated with Glasstual without having to modify each.

**DO** edit the file located at _[Configurations ➜ Build ➜ Code Signing Identity.xcconfig](Configurations/Build/Code%20Signing%20Identity.xcconfig)_

**It is HIGHLY DISCOURAGED to turn off code signing.** Certain features rely on the fact that Glasstual is properly signed and is within a sandboxed environment.

**GLASSTUAL DOES NOT REQUIRE A CERTIFICATE ISSUED BY APPLE TO BUILD** which means there is absolutely no reason to turn code signing off.

## Building Glasstual

The latest version of Glasstual requires a valid code signing certificate (it does not need to be issued by Apple) and Xcode 26 on macOS Tahoe 26.

This tree has **no paid-license or trial checks**. Precompiled store builds of Textual from codeux.com are a separate product.

**DO NOT change the Code Signing Identity setting through Xcode.** Modify the file located at _[Configurations ➜ Build ➜ Code Signing Identity.xcconfig](Configurations/Build/Code%20Signing%20Identity.xcconfig)_ instead.

Set your Apple Developer **Team ID** there, and set `GLASSTUAL_BUNDLE_IDENTIFIER` in `Configurations/Build/Standard Release/Glasstual.xcconfig` (and the Debug copy) to an identifier you own. This fork defaults to:

- Bundle ID: `com.vakesz.glasstual`
- Team ID: `H8W5DK3FN2`
- App Group: `H8W5DK3FN2.com.vakesz.glasstual`

Register that App ID and App Group on [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list), then enable **Automatic signing**.

Build Glasstual using the "Standard Release" build scheme.

### Software Updates

The Standard Release scheme builds with Sparkle enabled but **no `SUFeedURL`** — the
upstream Textual appcast was removed so that this fork can never offer Codeux's builds
as an update to itself. Set `SUFeedURL` in
_[Sources ➜ App ➜ Resources ➜ Property Lists ➜ Application Properties ➜ Info.plist](Sources/App/Resources/Property%20Lists/Application%20Properties/Info.plist)_
to your own appcast, or drop `GLASSTUAL_BUILT_WITH_SPARKLE_ENABLED` from
_Configurations ➜ Build ➜ Standard Release ➜ Enabled Features.xcconfig_ to compile
updating out entirely.

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

Unless stated otherwise by the [Acknowledgements.pdf](Acknowledgements.pdf) document, the license presented below shall govern the distribution of and modifications to; the work hosted by this repository.

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
