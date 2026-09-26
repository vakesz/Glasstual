# Glasstual

An IRC client for macOS 26 and later on Apple Silicon, built with Swift 6,
SwiftUI and AppKit.

[Download a release](https://github.com/vakesz/Glasstual/releases).
Updates are installed manually.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/website/assets/main-window-dark.png">
  <img src=".github/website/assets/main-window-light.png" alt="Glasstual showing servers, a conversation and the member list">
</picture>

## Features

- Multiple servers, favorites, unread filters and mentions.
- IRCv3 support, including SASL, typing notifications, replies, reactions,
  read markers and chat history.
- Lines and Bubbles transcript styles with light and dark appearances.
- Notifications, file transfers, local history and transcript logging.
- Slash-command suggestions, message rules and user scripts.

## Build

Requires an Apple Silicon Mac running macOS 26 or later and Xcode 27.

Set `DEVELOPMENT_TEAM` in `project.yml` for your signing team. Use your own
`GLASSTUAL_BUNDLE_IDENTIFIER` when building under another identity. Signing
must support the app's sandbox, app group and embedded XPC service.

```sh
make build
make run
```

`make build` generates the Xcode project from `project.yml`. Edit that file
for build settings, targets and entitlements. Generated project files stay
untracked. The Makefile installs pinned tools when needed and verifies their
checksums. Builds, test results and archives use Xcode's configured locations.
Tools are cached in `~/Library/Caches/Glasstual`; E2E logs go to
`~/Library/Logs/Glasstual`.

## Check changes

```sh
make generate
make build
make test
make e2e-fixtures
make lint
```

`make e2e-fixtures` checks loopback peers without launching the app.
`make e2e` runs the Accessibility tests in a disposable GUI login.
Use `make tsan` and `make smoke` for concurrency changes.
Run `make help` for all commands.

## Contribute

Read [AGENTS.md](AGENTS.md) for repository rules and
[Sources/App/README.md](Sources/App/README.md) for code ownership.

## Credits and license

Glasstual is an independent fork of
[Textual](https://github.com/Codeux-Software/Textual). Codeux Software, LLC
does not publish, endorse or support it.

See [LICENSE](LICENSE),
[Acknowledgements.pdf](Sources/App/Resources/Documentation/Acknowledgements.pdf)
and the [Cocoa Extensions provenance record](Sources/CocoaExtensions/PROVENANCE.md)
for copyright, license and attribution notices.
