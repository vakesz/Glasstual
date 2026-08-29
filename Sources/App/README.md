# `Sources/App` layout

The application target is organised by feature. A feature directory owns
everything that feature needs — its window or sheet controllers, its views, its
models and its localized strings — so a change to one part of the UI touches one
directory. Directories that are not features hold code with no single feature
owner.

| Directory | Holds |
| --- | --- |
| `Application/` | Process lifecycle and app-wide services: `main.swift`, `Application`, `ApplicationController`, `SharedApplication`/`AppController`, `WindowController`, the appearance and path/resource managers, the file logger, the dock icon and network reachability. |
| `Protocol/` | The IRC protocol engine, split by concern (`Client/`, `Inbound/`, `Outbound/`, `Negotiation/`, `Modes/`, `Presence/`, …). No AppKit window or sheet lives here. |
| `Preferences/` | The preference store (`Keys/`), themes (`Themes/`) and the Preferences window (`Dialog/`). |
| `Features/<Feature>/` | One directory per user-facing feature. |
| `UI/` | Shared AppKit building blocks with no feature owner: sheet and window base classes, alerts, prompts, popovers, table and field subclasses, appearance helpers. |
| `Localization/` | Strings with no single feature owner (`ApplicationStrings`, `PromptStrings`, `AccessibilityStrings`) plus formatting helpers. |
| `Resources/` | Nibs, asset catalogs, property lists, styles and scripts. Unchanged by this reorganisation. |

## Features

| Feature | Scope |
| --- | --- |
| `About` | The About window. |
| `AddressBook` | Ignore and notify entries for a server. |
| `ChannelProperties` | The channel properties sheet, its ban/access lists, invites and validation. |
| `ChannelSpotlight` | The channel spotlight search panel. |
| `ChannelView` | The message log: log controllers, renderer, WebKit view and scheme handler, link parsing, topic and mode editing. |
| `FileTransfer` | The file transfer dialog, its transfer controllers and DCC sockets. |
| `MainWindow` | The main window, its text input view, the menu bar action coordinator and input handling (history, key events, nickname completion). |
| `MemberList` | The channel member list, its cells, the user info popover and nickname colouring. |
| `Notifications` | Notification delivery: user notifications, sounds and speech. |
| `Onboarding` | The first-run onboarding window and its steps. |
| `Plugins` | Plugin discovery, loading and dispatch. |
| `Progress` | The shared progress indicator sheet. |
| `ServerChannelList` | The server-side channel list dialog. |
| `ServerList` | The server/channel outline view in the main window. |
| `ServerProperties` | The server properties sheet, endpoint and highlight lists, the network picker and nickname changes. |
| `Validation` | Text fields and combo boxes that validate their contents, and their shared strings. |

## Conventions

- A Swift file is named after its primary type. Files whose primary type still
  carries a legacy Objective-C prefix (`TXMenuController`, `TDCAlert`,
  `TVCLogScriptEventSink`, `TXMenuAction`) keep that name until the type itself
  is renamed. `@objc` runtime names are unchanged everywhere — nibs and the
  plugin API depend on them.
- Localized strings that belong to exactly one feature live in that feature's
  directory as `<Feature>Strings.swift`. Strings used by several features live
  in `Localization/`.
- `Sources/App` is globbed by `project.yml`; adding a new top-level directory
  under it needs a matching `sources:` entry for the `Glasstual` target.

## Move log

Every path below moved with `git mv`, so `git log --follow` still works. No file
contents changed. Files that were already in their feature directory
(`Features/About`, `Features/MainWindow` and the other feature-named string
files) are not listed because they did not move.

| Old path | New path |
| --- | --- |
| `Sources/App/Modules/ApplicationSupport/TXAppearance.swift` | `Sources/App/Application/Appearance.swift` |
| `Sources/App/Modules/ApplicationSupport/AppearanceTypes.swift` | `Sources/App/Application/AppearanceTypes.swift` |
| `Sources/App/Modules/AppKitSupport/TXApplication.swift` | `Sources/App/Application/Application.swift` |
| `Sources/App/Modules/ApplicationSupport/ApplicationController.swift` | `Sources/App/Application/ApplicationController.swift` |
| `Sources/App/Modules/ApplicationSupport/TPCApplicationInfo.swift` | `Sources/App/Application/ApplicationInfo.swift` |
| `Sources/App/Modules/AppKitSupport/TVCDockIcon.swift` | `Sources/App/Application/DockIcon.swift` |
| `Sources/App/Modules/ApplicationSupport/TLOFileLogger.swift` | `Sources/App/Application/FileLogger.swift` |
| `Sources/App/Modules/ApplicationSupport/TXGlobalModels.swift` | `Sources/App/Application/GlobalModels.swift` |
| `Sources/App/Modules/ApplicationSupport/ICLPayloadLocal.swift` | `Sources/App/Application/ICLPayloadLocal.swift` |
| `Sources/App/Modules/ApplicationSupport/NotificationSubscriptions.swift` | `Sources/App/Application/NotificationSubscriptions.swift` |
| `Sources/App/Modules/ApplicationSupport/TPCPathInfo.swift` | `Sources/App/Application/PathInfo.swift` |
| `Sources/App/Modules/Networking/OELReachability.swift` | `Sources/App/Application/Reachability.swift` |
| `Sources/App/Modules/ApplicationSupport/TPCResourceManager.swift` | `Sources/App/Application/ResourceManager.swift` |
| `Sources/App/Modules/ApplicationSupport/TPCResourceManagerDocumentTypeImporter.swift` | `Sources/App/Application/ResourceFileImporter.swift` |
| `Sources/App/Modules/ApplicationSupport/TXSharedApplication.swift` | `Sources/App/Application/SharedApplication.swift` |
| `Sources/App/Modules/AppKitSupport/TXWindowController.swift` | `Sources/App/Application/WindowController.swift` |
| `Sources/App/Modules/ApplicationSupport/main.swift` | `Sources/App/Application/main.swift` |
| `Sources/App/Modules/AppKitSupport/TDCAddressBookSheet.swift` | `Sources/App/Features/AddressBook/AddressBookSheet.swift` |
| `Sources/App/Features/ChannelAccessList/ChannelAccessListStrings.swift` | `Sources/App/Features/ChannelProperties/ChannelAccessListStrings.swift` |
| `Sources/App/Modules/AppKitSupport/TDCChannelBanListSheet.swift` | `Sources/App/Features/ChannelProperties/ChannelBanListSheet.swift` |
| `Sources/App/Features/ChannelInvite/ChannelInviteContent.swift` | `Sources/App/Features/ChannelProperties/ChannelInviteContent.swift` |
| `Sources/App/Features/ChannelInvite/ChannelInviteSheet.swift` | `Sources/App/Features/ChannelProperties/ChannelInviteSheet.swift` |
| `Sources/App/Features/ChannelInvite/ChannelInviteStrings.swift` | `Sources/App/Features/ChannelProperties/ChannelInviteStrings.swift` |
| `Sources/App/Features/ChannelInvite/ChannelInviteView.swift` | `Sources/App/Features/ChannelProperties/ChannelInviteView.swift` |
| `Sources/App/Modules/AppKitSupport/TDCChannelPropertiesSheet.swift` | `Sources/App/Features/ChannelProperties/ChannelPropertiesSheet.swift` |
| `Sources/App/Features/ChannelValidation/ChannelValidationPolicy.swift` | `Sources/App/Features/ChannelProperties/ChannelValidationPolicy.swift` |
| `Sources/App/Features/ChannelValidation/ChannelValidationStrings.swift` | `Sources/App/Features/ChannelProperties/ChannelValidationStrings.swift` |
| `Sources/App/Modules/AppKitSupport/TVCNotificationConfigurationViewController.swift` | `Sources/App/Features/ChannelProperties/NotificationConfigurationViewController.swift` |
| `Sources/App/Modules/AppKitSupport/TDCChannelSpotlightAppearance.swift` | `Sources/App/Features/ChannelSpotlight/ChannelSpotlightAppearance.swift` |
| `Sources/App/Modules/AppKitSupport/TDCChannelSpotlightController.swift` | `Sources/App/Features/ChannelSpotlight/ChannelSpotlightController.swift` |
| `Sources/App/Modules/AppKitSupport/TDCChannelSpotlightControls.swift` | `Sources/App/Features/ChannelSpotlight/ChannelSpotlightControls.swift` |
| `Sources/App/Modules/AppKitSupport/TDCChannelSpotlightSearchResult.swift` | `Sources/App/Features/ChannelSpotlight/ChannelSpotlightSearchResult.swift` |
| `Sources/App/Modules/AppKitSupport/TDCChannelSpotlightSearchResultsTable.swift` | `Sources/App/Features/ChannelSpotlight/ChannelSpotlightSearchResultsTable.swift` |
| `Sources/App/Features/ChannelModes/ChannelMode.swift` | `Sources/App/Features/ChannelView/ChannelMode.swift` |
| `Sources/App/Features/ChannelModes/ChannelModesContent.swift` | `Sources/App/Features/ChannelView/ChannelModesContent.swift` |
| `Sources/App/Features/ChannelModes/ChannelModesModel.swift` | `Sources/App/Features/ChannelView/ChannelModesModel.swift` |
| `Sources/App/Features/ChannelModes/ChannelModesStrings.swift` | `Sources/App/Features/ChannelView/ChannelModesStrings.swift` |
| `Sources/App/Features/ChannelModes/ChannelModesView.swift` | `Sources/App/Features/ChannelView/ChannelModesView.swift` |
| `Sources/App/Features/ChannelModes/ChannelModifyModesSheet.swift` | `Sources/App/Features/ChannelView/ChannelModifyModesSheet.swift` |
| `Sources/App/Features/ChannelTopic/ChannelModifyTopicSheet.swift` | `Sources/App/Features/ChannelView/ChannelModifyTopicSheet.swift` |
| `Sources/App/Features/ChannelTopic/ChannelTopicContent.swift` | `Sources/App/Features/ChannelView/ChannelTopicContent.swift` |
| `Sources/App/Features/ChannelTopic/ChannelTopicModel.swift` | `Sources/App/Features/ChannelView/ChannelTopicModel.swift` |
| `Sources/App/Features/ChannelTopic/ChannelTopicStrings.swift` | `Sources/App/Features/ChannelView/ChannelTopicStrings.swift` |
| `Sources/App/Features/ChannelTopic/ChannelTopicView.swift` | `Sources/App/Features/ChannelView/ChannelTopicView.swift` |
| `Sources/App/Modules/AppKitSupport/HTMLEntities.swift` | `Sources/App/Features/ChannelView/HTMLEntities.swift` |
| `Sources/App/Features/ChannelTopic/IRCFormattingTopicEditor.swift` | `Sources/App/Features/ChannelView/IRCFormattingTopicEditor.swift` |
| `Sources/App/Classes/Library/TLOLinkParser.swift` | `Sources/App/Features/ChannelView/LinkParser.swift` |
| `Sources/App/Classes/Views/Channel View/TVCLogController.swift` | `Sources/App/Features/ChannelView/LogController.swift` |
| `Sources/App/Modules/AppKitSupport/TVCLogControllerHistoricLogFile.swift` | `Sources/App/Features/ChannelView/LogControllerHistoricLogFile.swift` |
| `Sources/App/Modules/AppKitSupport/TVCLogControllerInlineMediaService.swift` | `Sources/App/Features/ChannelView/LogControllerInlineMediaService.swift` |
| `Sources/App/Modules/AppKitSupport/TVCLogControllerOperationQueue.swift` | `Sources/App/Features/ChannelView/LogControllerOperationQueue.swift` |
| `Sources/App/Classes/Views/Main Window/TVCLogControllerRegistry.swift` | `Sources/App/Features/ChannelView/LogControllerRegistry.swift` |
| `Sources/App/Classes/Views/Channel View/TVCLogControllerRendering.swift` | `Sources/App/Features/ChannelView/LogControllerRendering.swift` |
| `Sources/App/Classes/Views/Channel View/TVCLogLine.swift` | `Sources/App/Features/ChannelView/LogLine.swift` |
| `Sources/App/Classes/Views/Channel View/LogLineTypes.swift` | `Sources/App/Features/ChannelView/LogLineTypes.swift` |
| `Sources/App/Modules/AppKitSupport/TVCLogPolicy.swift` | `Sources/App/Features/ChannelView/LogPolicy.swift` |
| `Sources/App/Classes/Views/Channel View/TVCLogRenderer.swift` | `Sources/App/Features/ChannelView/LogRenderer.swift` |
| `Sources/App/Classes/Views/Channel View/TVCLogView.swift` | `Sources/App/Features/ChannelView/LogView.swift` |
| `Sources/App/Classes/Views/Channel View/TVCLogViewContentPolicy.swift` | `Sources/App/Features/ChannelView/LogViewContentPolicy.swift` |
| `Sources/App/Classes/Views/Channel View/TVCLogViewInternalWK2.swift` | `Sources/App/Features/ChannelView/LogViewInternalWK2.swift` |
| `Sources/App/Classes/Views/Channel View/TVCLogViewSchemeHandler.swift` | `Sources/App/Features/ChannelView/LogViewSchemeHandler.swift` |
| `Sources/App/Classes/Library/TLOpenLink.swift` | `Sources/App/Features/ChannelView/OpenLink.swift` |
| `Sources/App/Classes/Views/Channel View/TVCLogScriptEventSink.swift` | `Sources/App/Features/ChannelView/TVCLogScriptEventSink.swift` |
| `Sources/App/Modules/AppKitSupport/UnicodeHelper.swift` | `Sources/App/Features/ChannelView/UnicodeHelper.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/FileTransferController+Connection.swift` | `Sources/App/Features/FileTransfer/FileTransferController+Connection.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/FileTransferController+FileIO.swift` | `Sources/App/Features/FileTransfer/FileTransferController+FileIO.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/FileTransferController+Lifecycle.swift` | `Sources/App/Features/FileTransfer/FileTransferController+Lifecycle.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/FileTransferController+Presentation.swift` | `Sources/App/Features/FileTransfer/FileTransferController+Presentation.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/FileTransferController+Socket.swift` | `Sources/App/Features/FileTransfer/FileTransferController+Socket.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/FileTransferDialog+DownloadDestination.swift` | `Sources/App/Features/FileTransfer/FileTransferDialog+DownloadDestination.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/FileTransferDialog+NetworkAddress.swift` | `Sources/App/Features/FileTransfer/FileTransferDialog+NetworkAddress.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/FileTransferDialog+Presentation.swift` | `Sources/App/Features/FileTransfer/FileTransferDialog+Presentation.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/FileTransferDialog+Table.swift` | `Sources/App/Features/FileTransfer/FileTransferDialog+Table.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/FileTransferDialog+Transfers.swift` | `Sources/App/Features/FileTransfer/FileTransferDialog+Transfers.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/TDCFileTransferDialog.swift` | `Sources/App/Features/FileTransfer/FileTransferDialog.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/TDCFileTransferDialogSocket.swift` | `Sources/App/Features/FileTransfer/FileTransferDialogSocket.swift` |
| `Sources/App/Modules/AppKitSupport/TDCFileTransferDialogTableCell.swift` | `Sources/App/Features/FileTransfer/FileTransferDialogTableCell.swift` |
| `Sources/App/Modules/Networking/TLOInternetAddressLookup.swift` | `Sources/App/Features/FileTransfer/InternetAddressLookup.swift` |
| `Sources/App/Classes/Dialogs/File Transfers/TDCFileTransferDialogTransferController.swift` | `Sources/App/Features/FileTransfer/TDCFileTransferDialogTransferController.swift` |
| `Sources/App/Modules/InputHandling/TLOInputHistory.swift` | `Sources/App/Features/MainWindow/InputHistory.swift` |
| `Sources/App/Modules/InputHandling/TLOKeyEventHandler.swift` | `Sources/App/Features/MainWindow/KeyEventHandler.swift` |
| `Sources/App/Classes/Views/Main Window/TVCMainWindow.swift` | `Sources/App/Features/MainWindow/MainWindow.swift` |
| `Sources/App/Modules/AppKitSupport/TVCMainWindowAppearance.swift` | `Sources/App/Features/MainWindow/MainWindowAppearance.swift` |
| `Sources/App/Modules/AppKitSupport/TVCMainWindowChannelView.swift` | `Sources/App/Features/MainWindow/MainWindowChannelView.swift` |
| `Sources/App/Classes/Views/Main Window/TVCMainWindowContent.swift` | `Sources/App/Features/MainWindow/MainWindowContent.swift` |
| `Sources/App/Modules/AppKitSupport/TVCMainWindowInputAccessoryView.swift` | `Sources/App/Features/MainWindow/MainWindowInputAccessoryView.swift` |
| `Sources/App/Modules/AppKitSupport/TVCMainWindowLoadingScreen.swift` | `Sources/App/Features/MainWindow/MainWindowLoadingScreen.swift` |
| `Sources/App/Classes/Views/Main Window/TVCMainWindowTextView.swift` | `Sources/App/Features/MainWindow/MainWindowTextView.swift` |
| `Sources/App/Modules/AppKitSupport/TVCMainWindowTextViewAppearance.swift` | `Sources/App/Features/MainWindow/MainWindowTextViewAppearance.swift` |
| `Sources/App/Classes/Views/Main Window/TVCMainWindowWorldSeams.swift` | `Sources/App/Features/MainWindow/MainWindowWorldSeams.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuActionCoordinator.swift` | `Sources/App/Features/MainWindow/MenuActionCoordinator.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuActionCoordinatorChannelView.swift` | `Sources/App/Features/MainWindow/MenuActionCoordinatorChannelView.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuActionCoordinatorDialogCallbacks.swift` | `Sources/App/Features/MainWindow/MenuActionCoordinatorDialogCallbacks.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuActionCoordinatorDialogs.swift` | `Sources/App/Features/MainWindow/MenuActionCoordinatorDialogs.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuActionCoordinatorEditing.swift` | `Sources/App/Features/MainWindow/MenuActionCoordinatorEditing.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuActionCoordinatorIRC.swift` | `Sources/App/Features/MainWindow/MenuActionCoordinatorIRC.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuActionCoordinatorLifecycle.swift` | `Sources/App/Features/MainWindow/MenuActionCoordinatorLifecycle.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuActionCoordinatorServerChannel.swift` | `Sources/App/Features/MainWindow/MenuActionCoordinatorServerChannel.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuActionCoordinatorSupport.swift` | `Sources/App/Features/MainWindow/MenuActionCoordinatorSupport.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuActionCoordinatorWindow.swift` | `Sources/App/Features/MainWindow/MenuActionCoordinatorWindow.swift` |
| `Sources/App/Modules/AppKitSupport/MenuCommand.swift` | `Sources/App/Features/MainWindow/MenuCommand.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuCommandValidation.swift` | `Sources/App/Features/MainWindow/MenuCommandValidation.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuPresentation.swift` | `Sources/App/Features/MainWindow/MenuPresentation.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuValidationPolicy.swift` | `Sources/App/Features/MainWindow/MenuValidationPolicy.swift` |
| `Sources/App/Features/MessageMenu/MessageMenuStrings.swift` | `Sources/App/Features/MainWindow/MessageMenuStrings.swift` |
| `Sources/App/Modules/InputHandling/TLONicknameCompletionStatus.swift` | `Sources/App/Features/MainWindow/NicknameCompletionStatus.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuAction.swift` | `Sources/App/Features/MainWindow/TXMenuAction.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuController.swift` | `Sources/App/Features/MainWindow/TXMenuController.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuControllerActions.swift` | `Sources/App/Features/MainWindow/TXMenuControllerActions.swift` |
| `Sources/App/Modules/AppKitSupport/TXMenuControllerDialogs.swift` | `Sources/App/Features/MainWindow/TXMenuControllerDialogs.swift` |
| `Sources/App/Modules/AppKitSupport/TVCTextFormatterMenu.swift` | `Sources/App/Features/MainWindow/TextFormatterMenu.swift` |
| `Sources/App/Modules/AppKitSupport/TVCTextViewWithIRCFormatter.swift` | `Sources/App/Features/MainWindow/TextViewWithIRCFormatter.swift` |
| `Sources/App/Modules/AppKitSupport/IRCChannelMemberListController.swift` | `Sources/App/Features/MemberList/IRCChannelMemberListController.swift` |
| `Sources/App/Modules/UserPresentation/IRCUserNicknameColorStyleGenerator.swift` | `Sources/App/Features/MemberList/IRCUserNicknameColorStyleGenerator.swift` |
| `Sources/App/Classes/Views/User List/TVCMemberList.swift` | `Sources/App/Features/MemberList/MemberList.swift` |
| `Sources/App/Modules/AppKitSupport/TVCMemberListCell.swift` | `Sources/App/Features/MemberList/MemberListCell.swift` |
| `Sources/App/Modules/AppKitSupport/TVCMemberListUserInfoPopover.swift` | `Sources/App/Features/MemberList/MemberListUserInfoPopover.swift` |
| `Sources/App/Features/NicknameColor/NicknameColorContent.swift` | `Sources/App/Features/MemberList/NicknameColorContent.swift` |
| `Sources/App/Features/NicknameColor/NicknameColorModel.swift` | `Sources/App/Features/MemberList/NicknameColorModel.swift` |
| `Sources/App/Features/NicknameColor/NicknameColorSheet.swift` | `Sources/App/Features/MemberList/NicknameColorSheet.swift` |
| `Sources/App/Features/NicknameColor/NicknameColorStrings.swift` | `Sources/App/Features/MemberList/NicknameColorStrings.swift` |
| `Sources/App/Features/NicknameColor/NicknameColorView.swift` | `Sources/App/Features/MemberList/NicknameColorView.swift` |
| `Sources/App/Modules/Notifications/IRCClientNotificationPolicy.swift` | `Sources/App/Features/Notifications/IRCClientNotificationPolicy.swift` |
| `Sources/App/Modules/Notifications/IRCClientNotifications.swift` | `Sources/App/Features/Notifications/IRCClientNotifications.swift` |
| `Sources/App/Modules/Notifications/TLONotificationConfiguration.swift` | `Sources/App/Features/Notifications/NotificationConfiguration.swift` |
| `Sources/App/Modules/Notifications/TLONotificationController.swift` | `Sources/App/Features/Notifications/NotificationController.swift` |
| `Sources/App/Modules/Notifications/NotificationEvent.swift` | `Sources/App/Features/Notifications/NotificationEvent.swift` |
| `Sources/App/Modules/Notifications/NotificationStrings.swift` | `Sources/App/Features/Notifications/NotificationStrings.swift` |
| `Sources/App/Modules/Notifications/TLOSoundPlayer.swift` | `Sources/App/Features/Notifications/SoundPlayer.swift` |
| `Sources/App/Modules/Notifications/TLOSpeechSynthesizer.swift` | `Sources/App/Features/Notifications/SpeechSynthesizer.swift` |
| `Sources/App/Modules/Notifications/TLOSpeechSynthesizerEngine.swift` | `Sources/App/Features/Notifications/SpeechSynthesizerEngine.swift` |
| `Sources/App/Modules/Notifications/TLOSpokenNotification.swift` | `Sources/App/Features/Notifications/SpokenNotification.swift` |
| `Sources/App/Modules/AppKitSupport/TDCOnboardingAppearanceStepViewController.swift` | `Sources/App/Features/Onboarding/OnboardingAppearanceStepViewController.swift` |
| `Sources/App/Modules/AppKitSupport/TDCOnboardingIdentityStepViewController.swift` | `Sources/App/Features/Onboarding/OnboardingIdentityStepViewController.swift` |
| `Sources/App/Modules/AppKitSupport/TDCOnboardingNetworkStepViewController.swift` | `Sources/App/Features/Onboarding/OnboardingNetworkStepViewController.swift` |
| `Sources/App/Modules/AppKitSupport/TDCOnboardingNotificationsStepViewController.swift` | `Sources/App/Features/Onboarding/OnboardingNotificationsStepViewController.swift` |
| `Sources/App/Modules/AppKitSupport/TDCOnboardingStepViewController.swift` | `Sources/App/Features/Onboarding/OnboardingStepViewController.swift` |
| `Sources/App/Modules/AppKitSupport/TDCOnboardingStylePreviewView.swift` | `Sources/App/Features/Onboarding/OnboardingStylePreviewView.swift` |
| `Sources/App/Modules/AppKitSupport/TDCOnboardingWindowController.swift` | `Sources/App/Features/Onboarding/OnboardingWindowController.swift` |
| `Sources/App/Modules/AppKitSupport/THOPluginDispatcher.swift` | `Sources/App/Features/Plugins/PluginDispatcher.swift` |
| `Sources/App/Modules/AppKitSupport/THOPluginDispatcherSupport.swift` | `Sources/App/Features/Plugins/PluginDispatcherSupport.swift` |
| `Sources/App/Modules/AppKitSupport/PluginHostAdapter.swift` | `Sources/App/Features/Plugins/PluginHostAdapter.swift` |
| `Sources/App/Modules/AppKitSupport/THOPluginItem.swift` | `Sources/App/Features/Plugins/PluginItem.swift` |
| `Sources/App/Modules/AppKitSupport/THOPluginItemLogging.swift` | `Sources/App/Features/Plugins/PluginItemLogging.swift` |
| `Sources/App/Modules/AppKitSupport/THOPluginManager.swift` | `Sources/App/Features/Plugins/PluginManager.swift` |
| `Sources/App/Features/ProgressIndicator/ProgressIndicatorContent.swift` | `Sources/App/Features/Progress/ProgressIndicatorContent.swift` |
| `Sources/App/Features/ProgressIndicator/ProgressIndicatorModel.swift` | `Sources/App/Features/Progress/ProgressIndicatorModel.swift` |
| `Sources/App/Features/ProgressIndicator/ProgressIndicatorSheet.swift` | `Sources/App/Features/Progress/ProgressIndicatorSheet.swift` |
| `Sources/App/Features/ProgressIndicator/ProgressIndicatorStrings.swift` | `Sources/App/Features/Progress/ProgressIndicatorStrings.swift` |
| `Sources/App/Features/ProgressIndicator/ProgressIndicatorView.swift` | `Sources/App/Features/Progress/ProgressIndicatorView.swift` |
| `Sources/App/Modules/AppKitSupport/IRCClientDialogPresentation.swift` | `Sources/App/Features/ServerChannelList/IRCClientDialogPresentation.swift` |
| `Sources/App/Modules/AppKitSupport/TDCServerChannelListDialog.swift` | `Sources/App/Features/ServerChannelList/ServerChannelListDialog.swift` |
| `Sources/App/Modules/AppKitSupport/TVCChannelSelectionOutlineCellView.swift` | `Sources/App/Features/ServerList/ChannelSelectionOutlineCellView.swift` |
| `Sources/App/Modules/AppKitSupport/TVCChannelSelectionViewController.swift` | `Sources/App/Features/ServerList/ChannelSelectionViewController.swift` |
| `Sources/App/Modules/AppKitSupport/TVCContentNavigationOutlineView.swift` | `Sources/App/Features/ServerList/ContentNavigationOutlineView.swift` |
| `Sources/App/Modules/AppKitSupport/TVCServerList.swift` | `Sources/App/Features/ServerList/ServerList.swift` |
| `Sources/App/Modules/AppKitSupport/TVCServerListCell.swift` | `Sources/App/Features/ServerList/ServerListCell.swift` |
| `Sources/App/Features/HighlightEntry/HighlightEntryContent.swift` | `Sources/App/Features/ServerProperties/HighlightEntryContent.swift` |
| `Sources/App/Features/HighlightEntry/HighlightEntryModel.swift` | `Sources/App/Features/ServerProperties/HighlightEntryModel.swift` |
| `Sources/App/Features/HighlightEntry/HighlightEntrySelection.swift` | `Sources/App/Features/ServerProperties/HighlightEntrySelection.swift` |
| `Sources/App/Features/HighlightEntry/HighlightEntrySheet.swift` | `Sources/App/Features/ServerProperties/HighlightEntrySheet.swift` |
| `Sources/App/Features/HighlightEntry/HighlightEntryStrings.swift` | `Sources/App/Features/ServerProperties/HighlightEntryStrings.swift` |
| `Sources/App/Features/HighlightEntry/HighlightEntryView.swift` | `Sources/App/Features/ServerProperties/HighlightEntryView.swift` |
| `Sources/App/Modules/AppKitSupport/NetworkPickerDetailView.swift` | `Sources/App/Features/ServerProperties/NetworkPickerDetailView.swift` |
| `Sources/App/Modules/AppKitSupport/TDCNetworkPickerViewController.swift` | `Sources/App/Features/ServerProperties/NetworkPickerViewController.swift` |
| `Sources/App/Features/ServerNicknameChange/ServerChangeNicknameSheet.swift` | `Sources/App/Features/ServerProperties/ServerChangeNicknameSheet.swift` |
| `Sources/App/Modules/AppKitSupport/TDCServerEndpointListSheet.swift` | `Sources/App/Features/ServerProperties/ServerEndpointListSheet.swift` |
| `Sources/App/Modules/AppKitSupport/TDCServerEndpointListSheetTable.swift` | `Sources/App/Features/ServerProperties/ServerEndpointListSheetTable.swift` |
| `Sources/App/Features/ServerEndpoints/ServerEndpointStrings.swift` | `Sources/App/Features/ServerProperties/ServerEndpointStrings.swift` |
| `Sources/App/Modules/AppKitSupport/TDCServerHighlightListSheet.swift` | `Sources/App/Features/ServerProperties/ServerHighlightListSheet.swift` |
| `Sources/App/Features/ServerNicknameChange/ServerNicknameChangeContent.swift` | `Sources/App/Features/ServerProperties/ServerNicknameChangeContent.swift` |
| `Sources/App/Features/ServerNicknameChange/ServerNicknameChangeModel.swift` | `Sources/App/Features/ServerProperties/ServerNicknameChangeModel.swift` |
| `Sources/App/Features/ServerNicknameChange/ServerNicknameChangeStrings.swift` | `Sources/App/Features/ServerProperties/ServerNicknameChangeStrings.swift` |
| `Sources/App/Features/ServerNicknameChange/ServerNicknameChangeView.swift` | `Sources/App/Features/ServerProperties/ServerNicknameChangeView.swift` |
| `Sources/App/Classes/Dialogs/TDCServerPropertiesSheet.swift` | `Sources/App/Features/ServerProperties/ServerPropertiesSheet.swift` |
| `Sources/App/Classes/Dialogs/TDCServerPropertiesSheetCommandsAndChannels.swift` | `Sources/App/Features/ServerProperties/ServerPropertiesSheetCommandsAndChannels.swift` |
| `Sources/App/Classes/Dialogs/TDCServerPropertiesSheetConnection.swift` | `Sources/App/Features/ServerProperties/ServerPropertiesSheetConnection.swift` |
| `Sources/App/Classes/Dialogs/TDCServerPropertiesSheetIdentity.swift` | `Sources/App/Features/ServerProperties/ServerPropertiesSheetIdentity.swift` |
| `Sources/App/Classes/Dialogs/TDCServerPropertiesSheetProxyAndTLS.swift` | `Sources/App/Features/ServerProperties/ServerPropertiesSheetProxyAndTLS.swift` |
| `Sources/App/Classes/Dialogs/TDCServerPropertiesSheetValidation.swift` | `Sources/App/Features/ServerProperties/ServerPropertiesSheetValidation.swift` |
| `Sources/App/Modules/AppKitSupport/TVCValidatedComboBox.swift` | `Sources/App/Features/Validation/ValidatedComboBox.swift` |
| `Sources/App/Modules/AppKitSupport/TVCValidatedTextField.swift` | `Sources/App/Features/Validation/ValidatedTextField.swift` |
| `Sources/App/Features/Accessibility/AccessibilityStrings.swift` | `Sources/App/Localization/AccessibilityStrings.swift` |
| `Sources/App/Modules/Localization/ApplicationStrings.swift` | `Sources/App/Localization/ApplicationStrings.swift` |
| `Sources/App/Modules/Localization/LocalizedByteCount.swift` | `Sources/App/Localization/LocalizedByteCount.swift` |
| `Sources/App/Modules/Localization/PromptStrings.swift` | `Sources/App/Localization/PromptStrings.swift` |
| `Sources/App/Classes/Dialogs/Preferences/TDCPreferencesController.swift` | `Sources/App/Preferences/Dialog/PreferencesController.swift` |
| `Sources/App/Classes/Dialogs/Preferences/TDCPreferencesSupport.swift` | `Sources/App/Preferences/Dialog/PreferencesSupport.swift` |
| `Sources/App/Modules/AppKitSupport/TDCPreferencesUserStyleSheet.swift` | `Sources/App/Preferences/Dialog/PreferencesUserStyleSheet.swift` |
| `Sources/App/Classes/Preferences/Keys/ObservablePreferences.swift` | `Sources/App/Preferences/Keys/ObservablePreferences.swift` |
| `Sources/App/Classes/Preferences/Keys/PreferenceCatalog.swift` | `Sources/App/Preferences/Keys/PreferenceCatalog.swift` |
| `Sources/App/Classes/Preferences/Keys/PreferenceColor.swift` | `Sources/App/Preferences/Keys/PreferenceColor.swift` |
| `Sources/App/Classes/Preferences/Keys/Preferences+Appearance.swift` | `Sources/App/Preferences/Keys/Preferences+Appearance.swift` |
| `Sources/App/Classes/Preferences/Keys/Preferences+Connection.swift` | `Sources/App/Preferences/Keys/Preferences+Connection.swift` |
| `Sources/App/Classes/Preferences/Keys/Preferences+FileTransfers.swift` | `Sources/App/Preferences/Keys/Preferences+FileTransfers.swift` |
| `Sources/App/Classes/Preferences/Keys/Preferences+Input.swift` | `Sources/App/Preferences/Keys/Preferences+Input.swift` |
| `Sources/App/Classes/Preferences/Keys/Preferences+Internal.swift` | `Sources/App/Preferences/Keys/Preferences+Internal.swift` |
| `Sources/App/Classes/Preferences/Keys/Preferences+Messages.swift` | `Sources/App/Preferences/Keys/Preferences+Messages.swift` |
| `Sources/App/Classes/Preferences/Keys/Preferences+Notifications.swift` | `Sources/App/Preferences/Keys/Preferences+Notifications.swift` |
| `Sources/App/Classes/Preferences/PreferenceTypes.swift` | `Sources/App/Preferences/PreferenceTypes.swift` |
| `Sources/App/Classes/Preferences/TPCPreferencesClientSnapshot.swift` | `Sources/App/Preferences/PreferencesClientSnapshot.swift` |
| `Sources/App/Modules/ApplicationSupport/TPCPreferencesImportExport.swift` | `Sources/App/Preferences/PreferencesImportExport.swift` |
| `Sources/App/Classes/Preferences/TPCPreferencesLocal.swift` | `Sources/App/Preferences/PreferencesLocal.swift` |
| `Sources/App/Modules/ApplicationSupport/TPCPreferencesReload.swift` | `Sources/App/Preferences/PreferencesReload.swift` |
| `Sources/App/Features/Preferences/PreferencesStrings.swift` | `Sources/App/Preferences/PreferencesStrings.swift` |
| `Sources/App/Modules/ApplicationSupport/TPCPreferencesUserDefaultsLocal.swift` | `Sources/App/Preferences/PreferencesUserDefaultsLocal.swift` |
| `Sources/App/Classes/Preferences/Themes/TPCTheme.swift` | `Sources/App/Preferences/Themes/Theme.swift` |
| `Sources/App/Classes/Preferences/Themes/TPCThemeController.swift` | `Sources/App/Preferences/Themes/ThemeController.swift` |
| `Sources/App/Classes/Preferences/Themes/ThemeTypes.swift` | `Sources/App/Preferences/Themes/ThemeTypes.swift` |
| `Sources/App/Features/UserStyle/UserStyleStrings.swift` | `Sources/App/Preferences/UserStyleStrings.swift` |
| `Sources/App/Modules/IRCProtocol/Client/ClientEnvironment.swift` | `Sources/App/Protocol/Client/ClientEnvironment.swift` |
| `Sources/App/Modules/IRCProtocol/Client/ClientOutput.swift` | `Sources/App/Protocol/Client/ClientOutput.swift` |
| `Sources/App/Modules/IRCProtocol/Client/IRCClient.swift` | `Sources/App/Protocol/Client/IRCClient.swift` |
| `Sources/App/Modules/IRCProtocol/Client/IRCClientBouncerSupport.swift` | `Sources/App/Protocol/Client/IRCClientBouncerSupport.swift` |
| `Sources/App/Modules/IRCProtocol/Client/IRCClientComputedProperties.swift` | `Sources/App/Protocol/Client/IRCClientComputedProperties.swift` |
| `Sources/App/Classes/IRC/IRCClientConfig.swift` | `Sources/App/Protocol/Client/IRCClientConfig.swift` |
| `Sources/App/Classes/IRC/IRCClientConfigCoding.swift` | `Sources/App/Protocol/Client/IRCClientConfigCoding.swift` |
| `Sources/App/Classes/IRC/IRCClientConfigEncoding.swift` | `Sources/App/Protocol/Client/IRCClientConfigEncoding.swift` |
| `Sources/App/Classes/IRC/IRCClientConfigMigration.swift` | `Sources/App/Protocol/Client/IRCClientConfigMigration.swift` |
| `Sources/App/Modules/IRCProtocol/Client/IRCClientConfigurationLifecycle.swift` | `Sources/App/Protocol/Client/IRCClientConfigurationLifecycle.swift` |
| `Sources/App/Modules/IRCProtocol/Client/IRCClientTimer.swift` | `Sources/App/Protocol/Client/IRCClientTimer.swift` |
| `Sources/App/Modules/IRCProtocol/Client/IRCClientTypes.swift` | `Sources/App/Protocol/Client/IRCClientTypes.swift` |
| `Sources/App/Modules/IRCProtocol/Client/IRCClientWireUtilities.swift` | `Sources/App/Protocol/Client/IRCClientWireUtilities.swift` |
| `Sources/App/Modules/IRCProtocol/Commands/IRCClientChannelCommandDispatch.swift` | `Sources/App/Protocol/Commands/IRCClientChannelCommandDispatch.swift` |
| `Sources/App/Modules/IRCProtocol/Commands/IRCClientCommandDispatch.swift` | `Sources/App/Protocol/Commands/IRCClientCommandDispatch.swift` |
| `Sources/App/Modules/IRCProtocol/Commands/IRCClientCommandUtilities.swift` | `Sources/App/Protocol/Commands/IRCClientCommandUtilities.swift` |
| `Sources/App/Modules/IRCProtocol/Commands/IRCClientDefaultsCommandDispatch.swift` | `Sources/App/Protocol/Commands/IRCClientDefaultsCommandDispatch.swift` |
| `Sources/App/Modules/IRCProtocol/Commands/IRCClientIgnoreCommandDispatch.swift` | `Sources/App/Protocol/Commands/IRCClientIgnoreCommandDispatch.swift` |
| `Sources/App/Modules/IRCProtocol/Commands/IRCClientTimedCommands.swift` | `Sources/App/Protocol/Commands/IRCClientTimedCommands.swift` |
| `Sources/App/Modules/IRCProtocol/Commands/IRCClientTimerCommandDispatch.swift` | `Sources/App/Protocol/Commands/IRCClientTimerCommandDispatch.swift` |
| `Sources/App/Modules/IRCProtocol/Commands/IRCCommandIndex.swift` | `Sources/App/Protocol/Commands/IRCCommandIndex.swift` |
| `Sources/App/Modules/IRCProtocol/Commands/IRCCommandTypes.swift` | `Sources/App/Protocol/Commands/IRCCommandTypes.swift` |
| `Sources/App/Modules/IRCProtocol/Commands/IRCTimedCommand.swift` | `Sources/App/Protocol/Commands/IRCTimedCommand.swift` |
| `Sources/App/Modules/IRCProtocol/Commands/IRCUserCommand.swift` | `Sources/App/Protocol/Commands/IRCUserCommand.swift` |
| `Sources/App/Modules/IRCProtocol/Connection/IRCClientAutojoin.swift` | `Sources/App/Protocol/Connection/IRCClientAutojoin.swift` |
| `Sources/App/Modules/IRCProtocol/Connection/IRCClientConnectionDelegate.swift` | `Sources/App/Protocol/Connection/IRCClientConnectionDelegate.swift` |
| `Sources/App/Modules/IRCProtocol/Connection/IRCClientConnectionLifecycle.swift` | `Sources/App/Protocol/Connection/IRCClientConnectionLifecycle.swift` |
| `Sources/App/Modules/IRCProtocol/Connection/IRCClientConnectionTimers.swift` | `Sources/App/Protocol/Connection/IRCClientConnectionTimers.swift` |
| `Sources/App/Modules/IRCProtocol/Connection/IRCConnection.swift` | `Sources/App/Protocol/Connection/IRCConnection.swift` |
| `Sources/App/Modules/IRCProtocol/Delivery/IRCClientLabeledResponses.swift` | `Sources/App/Protocol/Delivery/IRCClientLabeledResponses.swift` |
| `Sources/App/Modules/IRCProtocol/Diagnostics/IRCClientRawTraffic.swift` | `Sources/App/Protocol/Diagnostics/IRCClientRawTraffic.swift` |
| `Sources/App/Modules/IRCProtocol/DirectChat/IRCClientDirectChat.swift` | `Sources/App/Protocol/DirectChat/IRCClientDirectChat.swift` |
| `Sources/App/Modules/IRCProtocol/DirectChat/IRCClientDirectChatDelegate.swift` | `Sources/App/Protocol/DirectChat/IRCClientDirectChatDelegate.swift` |
| `Sources/App/Modules/IRCProtocol/DirectChat/IRCDirectChatConnection.swift` | `Sources/App/Protocol/DirectChat/IRCDirectChatConnection.swift` |
| `Sources/App/Modules/IRCProtocol/FileTransfer/IRCClientDCCFileTransfer.swift` | `Sources/App/Protocol/FileTransfer/IRCClientDCCFileTransfer.swift` |
| `Sources/App/Modules/IRCProtocol/Filtering/IRCAddressBook.swift` | `Sources/App/Protocol/Filtering/IRCAddressBook.swift` |
| `Sources/App/Modules/IRCProtocol/Filtering/IRCAddressBookEntryMatcher.swift` | `Sources/App/Protocol/Filtering/IRCAddressBookEntryMatcher.swift` |
| `Sources/App/Modules/IRCProtocol/Filtering/IRCAddressBookMatchCache.swift` | `Sources/App/Protocol/Filtering/IRCAddressBookMatchCache.swift` |
| `Sources/App/Modules/IRCProtocol/Filtering/IRCClientAddressBook.swift` | `Sources/App/Protocol/Filtering/IRCClientAddressBook.swift` |
| `Sources/App/Modules/IRCProtocol/Filtering/IRCClientOutputSuppression.swift` | `Sources/App/Protocol/Filtering/IRCClientOutputSuppression.swift` |
| `Sources/App/Modules/IRCProtocol/Filtering/IRCHighlightLogEntry.swift` | `Sources/App/Protocol/Filtering/IRCHighlightLogEntry.swift` |
| `Sources/App/Modules/IRCProtocol/Filtering/IRCHighlightMatchCondition.swift` | `Sources/App/Protocol/Filtering/IRCHighlightMatchCondition.swift` |
| `Sources/App/Modules/IRCProtocol/Formatting/IRCClientTextEncoding.swift` | `Sources/App/Protocol/Formatting/IRCClientTextEncoding.swift` |
| `Sources/App/Modules/IRCProtocol/Formatting/IRCColorFormat.swift` | `Sources/App/Protocol/Formatting/IRCColorFormat.swift` |
| `Sources/App/Modules/AppKitSupport/NSStringHelper.swift` | `Sources/App/Protocol/Formatting/NSStringHelper.swift` |
| `Sources/App/Modules/IRCProtocol/History/IRCClientHistoryAndReadMarkers.swift` | `Sources/App/Protocol/History/IRCClientHistoryAndReadMarkers.swift` |
| `Sources/App/Modules/IRCProtocol/History/IRCClientNetsplitSummaries.swift` | `Sources/App/Protocol/History/IRCClientNetsplitSummaries.swift` |
| `Sources/App/Modules/IRCProtocol/IRCProtocolLimits.swift` | `Sources/App/Protocol/IRCProtocolLimits.swift` |
| `Sources/App/Modules/IRCProtocol/Identity/IRCClientNickServTokens.swift` | `Sources/App/Protocol/Identity/IRCClientNickServTokens.swift` |
| `Sources/App/Modules/IRCProtocol/Identity/IRCPrefix.swift` | `Sources/App/Protocol/Identity/IRCPrefix.swift` |
| `Sources/App/Classes/Library/TLOSCRAMClient.swift` | `Sources/App/Protocol/Identity/SCRAMClient.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientBatchProcessing.swift` | `Sources/App/Protocol/Inbound/IRCClientBatchProcessing.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientCTCPHandlers.swift` | `Sources/App/Protocol/Inbound/IRCClientCTCPHandlers.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientChannelEventHandlers.swift` | `Sources/App/Protocol/Inbound/IRCClientChannelEventHandlers.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientIdentityAndTags.swift` | `Sources/App/Protocol/Inbound/IRCClientIdentityAndTags.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientInboundDispatch.swift` | `Sources/App/Protocol/Inbound/IRCClientInboundDispatch.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientMembershipHandlers.swift` | `Sources/App/Protocol/Inbound/IRCClientMembershipHandlers.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientNumericChannels.swift` | `Sources/App/Protocol/Inbound/IRCClientNumericChannels.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientNumericConnection.swift` | `Sources/App/Protocol/Inbound/IRCClientNumericConnection.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientNumericErrors.swift` | `Sources/App/Protocol/Inbound/IRCClientNumericErrors.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientNumericReplies.swift` | `Sources/App/Protocol/Inbound/IRCClientNumericReplies.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientNumericTracking.swift` | `Sources/App/Protocol/Inbound/IRCClientNumericTracking.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientNumericWHOIS.swift` | `Sources/App/Protocol/Inbound/IRCClientNumericWHOIS.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientServerRegistration.swift` | `Sources/App/Protocol/Inbound/IRCClientServerRegistration.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientTextMessageHandlers.swift` | `Sources/App/Protocol/Inbound/IRCClientTextMessageHandlers.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCClientWHOReplies.swift` | `Sources/App/Protocol/Inbound/IRCClientWHOReplies.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCLineParser.swift` | `Sources/App/Protocol/Inbound/IRCLineParser.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCMessage.swift` | `Sources/App/Protocol/Inbound/IRCMessage.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCMessageBatch.swift` | `Sources/App/Protocol/Inbound/IRCMessageBatch.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCMessageTagParser.swift` | `Sources/App/Protocol/Inbound/IRCMessageTagParser.swift` |
| `Sources/App/Modules/IRCProtocol/Inbound/IRCNumeric.swift` | `Sources/App/Protocol/Inbound/IRCNumeric.swift` |
| `Sources/App/Modules/IRCProtocol/Localization/IRCCTCPStrings.swift` | `Sources/App/Protocol/Localization/IRCCTCPStrings.swift` |
| `Sources/App/Modules/IRCProtocol/Localization/IRCCommandStrings.swift` | `Sources/App/Protocol/Localization/IRCCommandStrings.swift` |
| `Sources/App/Modules/IRCProtocol/Localization/IRCConnectionStrings.swift` | `Sources/App/Protocol/Localization/IRCConnectionStrings.swift` |
| `Sources/App/Modules/IRCProtocol/Localization/IRCDiagnosticStrings.swift` | `Sources/App/Protocol/Localization/IRCDiagnosticStrings.swift` |
| `Sources/App/Modules/IRCProtocol/Localization/IRCDirectChatStrings.swift` | `Sources/App/Protocol/Localization/IRCDirectChatStrings.swift` |
| `Sources/App/Modules/IRCProtocol/Localization/IRCISupportStrings.swift` | `Sources/App/Protocol/Localization/IRCISupportStrings.swift` |
| `Sources/App/Modules/IRCProtocol/Localization/IRCInboundStrings.swift` | `Sources/App/Protocol/Localization/IRCInboundStrings.swift` |
| `Sources/App/Modules/IRCProtocol/Logging/IRCClientLogFile.swift` | `Sources/App/Protocol/Logging/IRCClientLogFile.swift` |
| `Sources/App/Modules/IRCProtocol/Models/IRCChannel.swift` | `Sources/App/Protocol/Models/IRCChannel.swift` |
| `Sources/App/Modules/IRCProtocol/Models/IRCClientChannelDirectory.swift` | `Sources/App/Protocol/Models/IRCClientChannelDirectory.swift` |
| `Sources/App/Modules/IRCProtocol/Models/IRCClientChannelStorage.swift` | `Sources/App/Protocol/Models/IRCClientChannelStorage.swift` |
| `Sources/App/Modules/IRCProtocol/Models/IRCTreeItem.swift` | `Sources/App/Protocol/Models/IRCTreeItem.swift` |
| `Sources/App/Modules/IRCProtocol/Modes/IRCChannelModeKind.swift` | `Sources/App/Protocol/Modes/IRCChannelModeKind.swift` |
| `Sources/App/Modules/IRCProtocol/Modes/IRCChannelModeState.swift` | `Sources/App/Protocol/Modes/IRCChannelModeState.swift` |
| `Sources/App/Modules/IRCProtocol/Modes/IRCChannelModeSymbol.swift` | `Sources/App/Protocol/Modes/IRCChannelModeSymbol.swift` |
| `Sources/App/Modules/IRCProtocol/Modes/IRCClientModeChanges.swift` | `Sources/App/Protocol/Modes/IRCClientModeChanges.swift` |
| `Sources/App/Modules/IRCProtocol/Modes/IRCModeInfo.swift` | `Sources/App/Protocol/Modes/IRCModeInfo.swift` |
| `Sources/App/Modules/IRCProtocol/Modes/IRCModeParser.swift` | `Sources/App/Protocol/Modes/IRCModeParser.swift` |
| `Sources/App/Modules/IRCProtocol/Negotiation/IRCCapability.swift` | `Sources/App/Protocol/Negotiation/IRCCapability.swift` |
| `Sources/App/Modules/IRCProtocol/Negotiation/IRCCapabilityDefaults.swift` | `Sources/App/Protocol/Negotiation/IRCCapabilityDefaults.swift` |
| `Sources/App/Modules/IRCProtocol/Negotiation/IRCClientNegotiation.swift` | `Sources/App/Protocol/Negotiation/IRCClientNegotiation.swift` |
| `Sources/App/Modules/IRCProtocol/Negotiation/IRCISupportInfo.swift` | `Sources/App/Protocol/Negotiation/IRCISupportInfo.swift` |
| `Sources/App/Modules/IRCProtocol/Negotiation/IRCISupportTokenParser.swift` | `Sources/App/Protocol/Negotiation/IRCISupportTokenParser.swift` |
| `Sources/App/Modules/IRCProtocol/Negotiation/IRCServerQuirks.swift` | `Sources/App/Protocol/Negotiation/IRCServerQuirks.swift` |
| `Sources/App/Modules/IRCProtocol/NetworkCatalog/IRCExtras.swift` | `Sources/App/Protocol/NetworkCatalog/IRCExtras.swift` |
| `Sources/App/Modules/IRCProtocol/NetworkCatalog/IRCNetworkList.swift` | `Sources/App/Protocol/NetworkCatalog/IRCNetworkList.swift` |
| `Sources/App/Modules/IRCProtocol/NetworkCatalog/IRCServer.swift` | `Sources/App/Protocol/NetworkCatalog/IRCServer.swift` |
| `Sources/App/Modules/IRCProtocol/Outbound/IRCClientCTCPAndReactions.swift` | `Sources/App/Protocol/Outbound/IRCClientCTCPAndReactions.swift` |
| `Sources/App/Modules/IRCProtocol/Outbound/IRCClientJoining.swift` | `Sources/App/Protocol/Outbound/IRCClientJoining.swift` |
| `Sources/App/Modules/IRCProtocol/Outbound/IRCClientOutboundTransport.swift` | `Sources/App/Protocol/Outbound/IRCClientOutboundTransport.swift` |
| `Sources/App/Modules/IRCProtocol/Outbound/IRCClientTextSending.swift` | `Sources/App/Protocol/Outbound/IRCClientTextSending.swift` |
| `Sources/App/Modules/IRCProtocol/Outbound/IRCClientTypingNotifications.swift` | `Sources/App/Protocol/Outbound/IRCClientTypingNotifications.swift` |
| `Sources/App/Modules/IRCProtocol/Outbound/IRCClientWireCommands.swift` | `Sources/App/Protocol/Outbound/IRCClientWireCommands.swift` |
| `Sources/App/Modules/IRCProtocol/Outbound/IRCJoinBatching.swift` | `Sources/App/Protocol/Outbound/IRCJoinBatching.swift` |
| `Sources/App/Modules/IRCProtocol/Outbound/IRCSendingMessage.swift` | `Sources/App/Protocol/Outbound/IRCSendingMessage.swift` |
| `Sources/App/Modules/IRCProtocol/Plugins/IRCClientPluginDispatch.swift` | `Sources/App/Protocol/Plugins/IRCClientPluginDispatch.swift` |
| `Sources/App/Modules/IRCProtocol/Plugins/IRCClientScriptExecution.swift` | `Sources/App/Protocol/Plugins/IRCClientScriptExecution.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCAddressBookUserTracking.swift` | `Sources/App/Protocol/Presence/IRCAddressBookUserTracking.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCChannelConfig.swift` | `Sources/App/Protocol/Presence/IRCChannelConfig.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCChannelMemberList.swift` | `Sources/App/Protocol/Presence/IRCChannelMemberList.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCChannelUser.swift` | `Sources/App/Protocol/Presence/IRCChannelUser.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCClientChannelState.swift` | `Sources/App/Protocol/Presence/IRCClientChannelState.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCClientUserDirectory.swift` | `Sources/App/Protocol/Presence/IRCClientUserDirectory.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCClientUserTracking.swift` | `Sources/App/Protocol/Presence/IRCClientUserTracking.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCTypingTracker.swift` | `Sources/App/Protocol/Presence/IRCTypingTracker.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCUser.swift` | `Sources/App/Protocol/Presence/IRCUser.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCUserPersistentStore.swift` | `Sources/App/Protocol/Presence/IRCUserPersistentStore.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCUserRelations.swift` | `Sources/App/Protocol/Presence/IRCUserRelations.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCWorld.swift` | `Sources/App/Protocol/Presence/IRCWorld.swift` |
| `Sources/App/Modules/IRCProtocol/Presence/IRCWorldObserver.swift` | `Sources/App/Protocol/Presence/IRCWorldObserver.swift` |
| `Sources/App/Modules/IRCProtocol/Presentation/IRCClientHighlightsAndReachability.swift` | `Sources/App/Protocol/Presentation/IRCClientHighlightsAndReachability.swift` |
| `Sources/App/Modules/IRCProtocol/Presentation/IRCClientLinePresentation.swift` | `Sources/App/Protocol/Presentation/IRCClientLinePresentation.swift` |
| `Sources/App/Modules/IRCProtocol/Presentation/IRCClientThemeEvents.swift` | `Sources/App/Protocol/Presentation/IRCClientThemeEvents.swift` |
| `Sources/App/Modules/IRCProtocol/Presentation/ThemePresentationSchema.swift` | `Sources/App/Protocol/Presentation/ThemePresentationSchema.swift` |
| `Sources/App/Modules/IRCProtocol/Presentation/ThemeTemplateStore.swift` | `Sources/App/Protocol/Presentation/ThemeTemplateStore.swift` |
| `Sources/App/Modules/IRCProtocol/Requests/IRCClientPlayback.swift` | `Sources/App/Protocol/Requests/IRCClientPlayback.swift` |
| `Sources/App/Modules/IRCProtocol/Requests/IRCClientRequestedCommandPresentation.swift` | `Sources/App/Protocol/Requests/IRCClientRequestedCommandPresentation.swift` |
| `Sources/App/Modules/IRCProtocol/Requests/IRCClientRequestedCommands.swift` | `Sources/App/Protocol/Requests/IRCClientRequestedCommands.swift` |
| `Sources/App/Modules/IRCProtocol/TransportSecurity/IRCSTSCapabilityValues.swift` | `Sources/App/Protocol/TransportSecurity/IRCSTSCapabilityValues.swift` |
| `Sources/App/Modules/IRCProtocol/TransportSecurity/IRCSTSPolicy.swift` | `Sources/App/Protocol/TransportSecurity/IRCSTSPolicy.swift` |
| `Sources/App/Modules/IRCProtocol/TransportSecurity/IRCSTSPolicyStore.swift` | `Sources/App/Protocol/TransportSecurity/IRCSTSPolicyStore.swift` |
| `Sources/App/Modules/AppKitSupport/TXAppearanceHelper.swift` | `Sources/App/UI/AppearanceHelper.swift` |
| `Sources/App/Modules/AppKitSupport/TVCAppearance.swift` | `Sources/App/UI/AppearanceSchema.swift` |
| `Sources/App/Modules/AppKitSupport/TVCAutoExpandingField.swift` | `Sources/App/UI/AutoExpandingField.swift` |
| `Sources/App/Modules/AppKitSupport/TVCBasicTableView.swift` | `Sources/App/UI/BasicTableView.swift` |
| `Sources/App/Modules/AppKitSupport/TVCErrorMessagePopover.swift` | `Sources/App/UI/ErrorMessagePopover.swift` |
| `Sources/App/Modules/AppKitSupport/TVCErrorMessagePopoverController.swift` | `Sources/App/UI/ErrorMessagePopoverController.swift` |
| `Sources/App/Modules/AppKitSupport/TDCInputPrompt.swift` | `Sources/App/UI/InputPrompt.swift` |
| `Sources/App/Modules/AppKitSupport/NSColorHelper.swift` | `Sources/App/UI/NSColorHelper.swift` |
| `Sources/App/Modules/AppKitSupport/NSTableViewHelper.swift` | `Sources/App/UI/NSTableViewHelper.swift` |
| `Sources/App/Modules/AppKitSupport/NSViewHelper.swift` | `Sources/App/UI/NSViewHelper.swift` |
| `Sources/App/Modules/AppKitSupport/TDCPreferencesGroupBox.swift` | removed with the nib-drawn preference panes |
| `Sources/App/Modules/AppKitSupport/TDCReactionPopoverController.swift` | `Sources/App/UI/ReactionPopoverController.swift` |
| `Sources/App/Modules/AppKitSupport/TDCSheetBase.swift` | `Sources/App/UI/SheetBase.swift` |
| `Sources/App/Modules/AppKitSupport/SheetContextProtocols.swift` | `Sources/App/UI/SheetContextProtocols.swift` |
| `Sources/App/Modules/AppKitSupport/TDCAlert.swift` | `Sources/App/UI/TDCAlert.swift` |
| `Sources/App/Modules/AppKitSupport/TDCWindowBase.swift` | `Sources/App/UI/WindowBase.swift` |

Everything outside the app — frameworks, the vendored static libraries, the
three XPC services, plugins and shared cross-process declarations — is listed
with its target and isolation default in the "Targets" table of `AGENTS.md`.
