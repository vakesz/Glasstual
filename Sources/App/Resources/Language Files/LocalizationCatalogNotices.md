# Localization catalog notices

The following notice and license apply to every application String Catalog,
wherever it sits: the shared tables under
`Sources/App/Resources/Language Files`, and the feature-owned ones that live
beside the code that reads them under `Sources/App/Features` and
`Sources/App/Preferences`.

Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
Please see `Acknowledgements.pdf` for additional information.

The migrated source tables retain these original copyright ranges, listed under
the names their catalogs carry today:

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

The same notice and license apply to the bundled extension String Catalogs
under `Sources/Plugins`, with the original source-file copyright ranges:

* Caffeine and Chat Filter: Copyright (c) 2015 - 2018 Codeux Software, LLC &
  respective contributors. Chat Filter's `ChatFilter.xcstrings`,
  `ChatFilterEditor.xcstrings` and `ChatFilterLogic.xcstrings` were
  `TPI_ChatFilterExtension`, `TPI_ChatFilterEditFilterSheet` and
  `TPI_ChatFilterLogic`.
* Smiley Converter and User Insights: Copyright (c) 2013 - 2018 Codeux
  Software, LLC & respective contributors.
* System Profiler: Copyright (c) 2012 - 2020 Codeux Software, LLC & respective
  contributors.
* ZNC Additions: Copyright (c) 2011 - 2018 Codeux Software, LLC & respective
  contributors.

Please see `Acknowledgements.pdf` for additional information about these
bundled extensions.

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
