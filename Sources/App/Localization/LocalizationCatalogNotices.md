# Localization catalog notices

The following notice applies to every application String Catalog under
`Sources/App`:

Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
Please see `Acknowledgements.pdf` for additional information.

Catalogs assembled from earlier Textual tables retain their original
copyright ranges:

- `About.xcstrings`, `Accessibility.xcstrings`,
  `Application.xcstrings`, `ChannelSpotlight.xcstrings`,
  `FileTransfer.xcstrings`, `HighlightLog.xcstrings`,
  `MemberList.xcstrings`, `NetworkPicker.xcstrings`,
  `Notifications.xcstrings`, `Onboarding.xcstrings`,
  `ServerChannelList.xcstrings` and `ServerProperties.xcstrings`:
  Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
- `ChannelProperties.xcstrings` also contains the channel mask-list text that
  was `ChannelBanList.xcstrings`, copyrighted 2010 - 2018 by Codeux Software,
  LLC & respective contributors.
- `AddressBook.xcstrings`, `ChannelProperties.xcstrings` and
  `CommonErrors.xcstrings`:
  Copyright (c) 2018 Codeux Software, LLC & respective contributors.
- `IRC.xcstrings`, `MainWindow.xcstrings`, `Prompts.xcstrings` and
  `Settings.xcstrings`: Copyright (c) 2010 - 2020 Codeux Software, LLC &
  respective contributors.
- `MainWindow.xcstrings` also contains menu text copyrighted 2010 - 2018 by
  Codeux Software, LLC & respective contributors.
- `ChannelProperties.xcstrings` also contains invite text copyrighted
  2010 - 2018 by Codeux Software, LLC & respective contributors.
- `Rules.xcstrings`, which now also holds the filter-editor text that was
  `RuleEditor.xcstrings`: Copyright (c) 2015 - 2018 Codeux Software, LLC &
  respective contributors.
- `Bouncer.xcstrings`: Copyright (c) 2011 - 2018 Codeux Software, LLC &
  respective contributors.
- `prevent-sleep-while-connected` and `prevent-sleep-explanation` in
  `Settings.xcstrings`: Copyright (c) 2015 - 2018 Codeux Software, LLC &
  respective contributors.

Portions of `ChannelProperties.xcstrings` and
`ServerProperties.xcstrings` are also:

Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>

The complete Textual and LimeChat license terms are in the repository's root
`LICENSE` file. Additional third-party notices are in
`Sources/App/Resources/Documentation/Acknowledgements.pdf`.

## Keys with no reader

These `Prompts.xcstrings` keys belonged to the import/export flow that came
before `SettingsTransfer`, and to three alert paths that no longer exist. The
accessors that read them are gone; the entries and their translations stay, so
that pruning them later is a deliberate decision rather than a discovery:

- `please-note-that-the-following-items-cannot-be-exported`,
  `this-action-will-save-a-copy`, `please-note-that-the-following-items`,
  `this-action-will-overwrite-your-configuration`,
  `your-current-preferences-could-not-be-backed-up`,
  `the-preferences-could-not-be-imported` and
  `the-selected-file-is-not-a-preferences-file`
- `choose-file`, `select`, `remove` and `do-not-show-this-message-again`
- `intentionally-empty-informative-text`,
  `are-you-sure-you-want-to-open-the-file-named` and
  `encryption-with-a-digital-certificate-keeps`
