# Localization catalog notices

The following notice and license apply to every application String Catalog,
wherever it sits. Every one of them now lives beside the code that reads it,
under `Sources/App/Features`, `Sources/App/Preferences`,
`Sources/App/Protocol` and `Sources/App/Localization`.

Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
Please see `Acknowledgements.pdf` for additional information.

The migrated source tables retain these original copyright ranges, listed under
the names those tables carried; the renames and merges below say which catalog
each one is part of today:

* `Accessibility.xcstrings`, `BasicLanguage.xcstrings`,
  `ChannelSpotlight.xcstrings`, `FileTransfers.xcstrings`,
  `Notifications.xcstrings`, `NotificationSettings.xcstrings`,
  `Onboarding.xcstrings`, `ServerChannelList.xcstrings`,
  `TDCAboutDialog.xcstrings`, `TDCChannelBanListSheet.xcstrings`,
  `TDCChannelInviteSheet.xcstrings`,
  `TDCServerEndpointListSheet.xcstrings`,
  `TDCServerHighlightListSheet.xcstrings`,
  `TDCServerPropertiesSheet.xcstrings`, and `TXMenuController.xcstrings`:
  Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
* `CommonErrors.xcstrings`, `TDCAddressBookSheet.xcstrings`,
  `TDCChannelModifyModesSheet.xcstrings`,
  `TDCChannelModifyTopicSheet.xcstrings`, and
  `TDCChannelPropertiesSheet.xcstrings`: Copyright (c) 2018 Codeux Software,
  LLC & respective contributors.
* `IRC.xcstrings`, `Prompts.xcstrings`, `Settings.xcstrings`, and
  `TVCMainWindow.xcstrings`: Copyright (c) 2010 - 2020 Codeux Software,
  LLC & respective contributors.

Six of those were renamed as they were migrated, so a diff against the
original tables reads as a rename rather than a deletion:
`ChannelSpotlight.xcstrings` was `TDCChannelSpotlightController`,
`FileTransfers.xcstrings` was `TDCFileTransferDialog`,
`NotificationSettings.xcstrings` was `TVCNotificationConfigurationView`,
`Onboarding.xcstrings` was `TDCOnboardingWindow`,
`ServerChannelList.xcstrings` was `TDCServerChannelListDialog`, and
`Settings.xcstrings` was `TDCPreferencesController`.

`NicknameColor.xcstrings` was `TDCNicknameColorSheet`, and carries the same
notice as the tables above.

Moving the catalogs beside their features renamed more of them, and merged the
ones a single feature reads into one table. A catalog's file name is its table
and its generated symbol namespace, so each line below is a rename of both:

* `About.xcstrings` was `TDCAboutDialog.xcstrings`.
* `AddressBook.xcstrings` was `TDCAddressBookSheet.xcstrings`.
* `Application.xcstrings` was `BasicLanguage.xcstrings`.
* `ChannelBanList.xcstrings` was `TDCChannelBanListSheet.xcstrings`.
* `ChannelTopic.xcstrings` was `TDCChannelModifyTopicSheet.xcstrings`.
* `HighlightEntry.xcstrings` was `TDCHighlightEntrySheet.xcstrings`.
* `ServerEndpointList.xcstrings` was `TDCServerEndpointListSheet.xcstrings`.
* `ChannelProperties.xcstrings` is `TDCChannelPropertiesSheet.xcstrings`,
  `TDCChannelInviteSheet.xcstrings` and
  `TDCChannelModifyModesSheet.xcstrings` merged.
* `MainWindow.xcstrings` is `TVCMainWindow.xcstrings` and
  `TXMenuController.xcstrings` merged.
* `MemberList.xcstrings` also holds what `NicknameColor.xcstrings` held.
* `Notifications.xcstrings` also holds what `NotificationSettings.xcstrings`
  held.
* `ServerProperties.xcstrings` is `TDCServerPropertiesSheet.xcstrings`,
  `TDCServerChangeNicknameSheet.xcstrings` and
  `TDCServerHighlightListSheet.xcstrings` merged.
* `Transcript.xcstrings` is `TranscriptView.xcstrings` and
  `TranscriptHistory.xcstrings` merged.

`TDCChannelModifyTopicSheet.xcstrings`, `TDCHighlightEntrySheet.xcstrings` and
`TDCServerEndpointListSheet.xcstrings` stayed separate tables rather than
joining the merge beside them: each shares a key with it that carries a
different string, so merging would have dropped one of the two.

The same notice and license apply to the catalogs the bundled extensions left
behind when their code was folded into the application, with the original
source-file copyright ranges:

* `Rules.xcstrings` and `RuleEditor.xcstrings`: Copyright (c) 2015 - 2018
  Codeux Software, LLC & respective contributors. They were the Chat Filter
  extension's `TPI_ChatFilterExtension`, `TPI_ChatFilterEditFilterSheet` and
  `TPI_ChatFilterLogic`; the first and last were merged, because their keys do
  not collide.
* `Bouncer.xcstrings`: Copyright (c) 2011 - 2018 Codeux Software, LLC &
  respective contributors. It was the ZNC Additions extension's
  `BasicLanguage.xcstrings`.
* `prevent-sleep-while-connected` and `prevent-sleep-explanation` in
  `Settings.xcstrings`: Copyright (c) 2015 - 2018 Codeux Software, LLC &
  respective contributors. They were the Caffeine extension's.

Please see `Acknowledgements.pdf` for additional information.

Portions of `TDCChannelInviteSheet.xcstrings` and
`TDCServerChangeNicknameSheet.xcstrings` are also:

Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
* Neither the name of Textual, "Codeux Software, LLC", nor the names of its
  contributors may be used to endorse or promote products derived from this
  software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
