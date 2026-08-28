# Preferences pane inventory

Taken from `Sources/App/Resources/User Interface/en.lproj/TDCPreferences.xib` before
the SwiftUI migration, one row per control. `Preference key` names the typed
declaration under `Sources/App/Preferences/Keys/` that the control drives; a
control that runs code rather than writing a key names the action instead.

Bindings written `-2.…` in the nib went through a `@objc dynamic` shim on
`PreferencesController`; the shim's underlying key is listed.

The 19 panes come from `PreferencesPaneCatalog.panes`. Add-on panes contributed
by plugins are appended to the Add-ons section at runtime and carry no controls
of their own.

## Toolbar sections and sub-pages

The window has one toolbar item per section. A section with several sub-pages
shows a picker above the form — segmented while its labels fit across the fixed
window width, a pop-up otherwise.

| Toolbar section | Symbol | Sub-page | Panes it draws |
| --- | --- | --- | --- |
| General | `gearshape` | — | General |
| Behavior | `slider.horizontal.3` | — | Behavior |
| Notifications | `bell` | — | Notifications |
| Highlights | `text.magnifyingglass` | — | Highlights |
| Interface | `macwindow` | — | Interface |
| Style | `paintbrush` | — | Style |
| Controls | `keyboard` | — | Controls |
| Add-ons | `puzzlepiece.extension` | Installed Add-ons | Installed Add-ons |
| Add-ons | | one per plugin | that plugin's own AppKit view |
| Advanced | `gearshape.2` | Connection | Compatibility, Flood Control, Incoming Data |
| Advanced | | Channels | Channel Management, Command Scope |
| Advanced | | Identity | Default Identity, Default IRCop Messages |
| Advanced | | Media | File Transfers, Inline Media |
| Advanced | | System | Log Location, Hidden |

The Add-ons picker is a pop-up rather than a segmented row: plugin titles are
supplied by the plugins, and the five installed ones already need more width
than the window has.

## General (`general`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Checkbox | Request confirmation before quitting Glasstual | `Connection.confirmQuit` |

## Behavior (`behavior`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Checkbox | Open browser links in the background | `Messages.openBrowserInBackground` |
| Checkbox | Automatically rejoin a channel when kicked | `Connection.rejoinOnKick` |
| Checkbox | Automatically join a channel when invited | `Connection.autojoinOnInvite` |
| Checkbox | Toggle away status when your display goes to sleep | `Connection.awayOnScreenSleep` |
| Checkbox | Restore scrollback from previous session | `Logging.reloadScrollbackOnLaunch` |
| Checkbox | Restore the state of queries from previous session | `Appearance.rememberQueryStates` |
| Checkbox | Send typing notifications | `Connection.sendTypingNotifications` |
| Footnote | Lets other people in a channel or query see when you are writing a message. | — |

## Notifications (`notifications`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Hosted AppKit view | Alerts (event table + per-event alert settings) | `NotificationConfigurationViewController`, `Notifications.*` per event |
| Checkbox | Only speak Channel Messages for the selected channel | `Notifications.onlySpeakForSelection` |
| Checkbox | Channel name | `Notifications.flag(.channelMessage, .speakChannelName)` (disabled while "only speak for selection") |
| Checkbox | Nickname | `Notifications.flag(.channelMessage, .speakNickname)` |
| Checkbox | Show number of unread private messages on Glasstual's Dock icon | `Notifications.displayDockBadge` |
| Checkbox | Show number of unread channel messages on Glasstual's Dock icon | `Notifications.publicMessageCountOnDockBadge` |
| Checkbox | Show notifications when Glasstual is focused | `Notifications.postWhileInFocus` |

## Highlights (`highlights`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Popup | Partial Matches / Full Word Matches / Regular Expression (ICU) | `Highlights.matchingMethod` |
| Checkbox | Log highlights to separate window | `Logging.logHighlights` + reload `.highlightLogging` |
| Checkbox | Highlight current nickname | `Highlights.trackLocalNickname` (disabled for regular expressions) |
| Table + add/remove | Highlight words | `Highlights.matchKeywords` |
| Table + add/remove | Exclude words | `Highlights.excludeKeywords` (disabled for regular expressions) |

## Interface (`interface`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Checkbox | Right to left text | `Messages.rightToLeftFormatting` + reload style |
| Popup | Main window appearance: System / Light / Dark | `Appearance.preferredAppearance` + reload `.appearance` |
| Popup | Arrange multiple channels: Top to bottom / Left to right | `Appearance.channelViewArrangement` + reload |
| Checkbox | Use "x" to indicate user with no mode set in user list | `Appearance.memberListNoModeSymbol` + reload badges |
| Checkbox | Place known server staff members at top of user list | `Appearance.memberListSortFavorsServerStaff` + reload sort order |
| Checkbox | User list info popover updates while scrolling | `Appearance.memberListUpdatesPopoverOnScroll` |
| Colour well | Background color for unread badge with highlight: | `Badges.serverListUnreadHighlight` + reload |
| Button | Reset | resets `Badges.serverListUnreadHighlight` |
| Colour wells ×6 | Server Staff Member / Channel Owner (+q) / Channel Administrator (+a) / Channel Operator (+o) / Channel Half-Operator (+h) / Voiced User (+v) | `UserListModeBadge.preferenceKey` per badge |
| Button | Reset to Defaults | resets all `Badges.userListMode` keys |

## Style (`style`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Popup | Style: | `Theme.name` through `ThemeController` + reload style |
| Button | Browse Style Files | opens the style folder (alert first for bundled styles) |
| Label | Font: | `Theme.fontName`, `Theme.fontSize` |
| Button | Change | opens `NSFontPanel` |
| Checkbox | Automatically add scrollback markers | `Messages.autoAddScrollbackMark` |
| Checkbox | Show date changes | `Messages.showDateChanges` + reload style |
| Checkbox | Show general event messages | `Messages.showJoinLeave` |
| Checkbox | Automatically reload custom styles when they change | `Theme.reloadCustomThemesOnChange` |
| Button | Modify Custom Style Sheet Rules | `PreferencesUserStyleSheet` (AppKit sheet) |
| Combo box | Scrollback Save Limit: | `Logging.scrollbackSaveLimit`, clamped 100…50000 |
| Combo box | Nickname Format: | `Theme.nicknameFormat`, enabled by `Theme.nicknameFormatIsUserConfigurable` |
| Combo box | Timestamp Format: | `Theme.timestampFormat`, enabled by `Theme.timestampFormatIsUserConfigurable` |
| Checkbox | Disable nickname colors | `Messages.disableNicknameColorHashing` + reload style |
| Checkbox | Show mode symbol in front of inline nicknames | `Appearance.conversationTrackingIncludesModeSymbol` |
| Checkbox | Show server Message of the Day (MOTD) | `Connection.displayServerMOTD` |

## Controls (`controls`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Checkbox | Channel navigation is limited to the selected server | `Appearance.channelNavigationIsServerSpecific` |
| Popup | Double clicking a user: | `Input.userDoubleClickAction` |
| Popup | Command + W key action: | `Input.commandWKeyAction` |
| Checkbox | Connect to server on double click | `Appearance.connectOnDoubleClick` |
| Checkbox | Disconnect from server on double click | `Appearance.disconnectOnDoubleClick` |
| Checkbox | Join channel on double click | `Appearance.joinOnDoubleClick` |
| Checkbox | Leave channel on double click | `Appearance.leaveOnDoubleClick` |
| Checkbox | Automatically copy selected text | `Messages.copyOnSelect` |
| Checkbox | Check spelling while typing | `Input.automaticSpellCheck` |
| Checkbox | Check grammar while typing | `Input.automaticGrammarCheck` |
| Checkbox | Correct spelling automatically | `Input.automaticSpellCorrection` |
| Checkbox | Save input history for each channel rather than globally | `Input.historyIsChannelSpecific` + reload `.inputHistoryScope` |
| Checkbox | Command Return (⌘⏎) sends message as an action | `Input.commandReturnSendsAction` |
| Checkbox | Control Enter (⌃⎆) sends message instead of inserting new line | `Input.controlEnterSendsMessage` |
| Popup | Text size of the input text field: | `Input.textViewFontSize` + reload `.textFieldFontSize` |
| Popup | Tab key Action: | `Input.tabKeyAction` |
| Text field | Autocomplete Suffix: | `Input.tabCompletionSuffix` (live preview beside it) |

## Add-ons (`addons`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Table | The following custom commands are available: | `PluginManager` AppleScript + user input commands |
| Button | Open In Finder | opens the group container Application Support folder |

## Channel Management (`channelManagement`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Popup | Hostmask Ban Format: | `Commands.banFormat` |
| Text field | Default Kick Reason: | `Commands.kickMessage` |

## Command Scope (`commandScope`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Checkbox | /amsg and /ame apply to all connections | `Commands.amsgAllConnections` |
| Checkbox | /away applies to all connections | `Commands.awayAllConnections` |
| Checkbox | /nick applies to all connections | `Commands.nickAllConnections` |
| Checkbox | /clearall applies to all connections | `Commands.clearAllConnections` |
| Checkbox | Give focus to the destination of the /msg command | `Commands.giveFocusOnMessageCommand` |
| Radio ×3 | Forward notices to: Server Console / Selected Channel / Private Message | `Commands.noticeDestination` |

## Compatibility (`compatibility`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Checkbox | Enable echo-message capability | `Connection.echoMessageCapability` |

## Flood Control (`floodControl`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Slider 0.5…10.0 | Delay Between Channel Joins: | `Connection.autojoinDelayBetweenChannelJoins` |
| Slider 0.0…10.0 | Delay Before Channel Joins: | `Connection.autojoinDelayAfterIdentification` |
| Slider 0…2000 | WHO Command Maximum Channel Size: | `Appearance.trackUserAwayStatusMaximumChannelSize` |

## Incoming Data (`incomingData`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Checkbox | Automatically reply to Client-to-Client (CTCP) requests | `Messages.replyToCTCPRequests` |
| Checkbox | Automatically ignore highlight spam | `Messages.detectHighlightSpam` |
| Checkbox | Remove formatting from incoming messages | `Messages.removeAllFormatting` |
| Checkbox | Replace Combining Diacritical Marks with ﷐ | `Messages.filterUnicodeTextSpam` |

## File Transfers (`fileTransfers`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Popup | When file transfer request is received: | `FileTransfers.requestReplyAction` |
| Popup | IP Address detection method: | `FileTransfers.ipAddressDetectionMethod` |
| Text field | Manually entered IP address: | `FileTransfers.manuallyEnteredIPAddress` (enabled for Manual only) |
| Text fields | File transfer port range: … to … | `FileTransfers.portRangeStart`, `FileTransfers.portRangeEnd`, clamped 1024…65535 |
| Popup | Download files to the folder: | `FileTransferDialog.downloadDestinationURL` (security-scoped bookmark) |
| Checkbox | Send passive file transfer requests | `FileTransfers.requestsAreReversed` |
| Checkbox | Do not allow Mac to go to sleep while transferring a file | `FileTransfers.preventIdleSystemSleep` |

## Inline Media (`inlineMedia`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Checkbox | Show images, videos, and other media inline with chat | `Messages.showInlineMedia`, asks permission before enabling |
| Popup | Do not display images with a file size greater than | `InlineMedia.maximumFilesize` |
| Text field | Do not display images with a height greater than … pixels | `InlineMedia.maximumHeight`, clamped 0…6000 |
| Text field | Scale to a maximum of … pixels wide | `InlineMedia.scalingWidth`, clamped 40…2000 |
| Checkbox | Load everything | `InlineMedia.checkEverything` |
| Checkbox | Only inline images and videos | `InlineMedia.limitToBasics` |
| Checkbox | Including video services such as YouTube and others | `InlineMedia.limitBasicsToFiles` (enabled by the checkbox above) |
| Checkbox | Only inline media that is safe to view in public | `InlineMedia.limitNaughtyContent` |
| Checkbox | Only inline media from safe sources | `InlineMedia.limitUnsafeContent` |

## Log Location (`logLocation`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Checkbox | Log transcripts to folder: | `Logging.logToDisk` |
| Popup | (destination) / Select Destination… / Clear Destination | `Logging.transcriptFolderBookmark` via `PathInfo` + reload `.logTranscripts` |

## Default Identity (`defaultIdentity`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Text field | Nickname: | `Identity.nickname` |
| Text field | Away Nickname: | `Identity.awayNickname` |
| Text field | Username: | `Identity.username` |
| Text field | Real name: | `Identity.realName` |

## Default IRCop Messages (`defaultIRCopMessages`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Text field | Default Kill Reason: | `Commands.irCopKillMessage` |
| Text field | Default G:Line Reason: | `Commands.irCopGlineMessage` |
| Text field | Default Shun Reason: | `Commands.irCopShunMessage` |

## Hidden (`hidden`)

| Control | Label | Preference key / action |
| --- | --- | --- |
| Checkbox | Enable App Nap | `Internals.appSleepDisabled` (inverted) |
| Checkbox | Limit number of processes spawned by WebKit2 | `Appearance.webViewProcessPoolLimited` |
| Checkbox | Enable link previews in WebKit2 | `Appearance.webViewPreviewLinks` |
| Checkbox | Enable custom scrollbars | `Appearance.webViewCustomScrollersDisabled` (inverted) |
| Checkbox | Load history lazily | `Logging.loadHistoryLazily` |
| Checkbox | Server list and user list appear transparent | `Appearance.disableSidebarTranslucency` (inverted) |
| Combo box | Scrollback Visible Limit: | `Logging.scrollbackVisibleLimit`, clamped 100…15000 or 0 |
