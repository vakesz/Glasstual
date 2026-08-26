/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

#import "GlasstualPrivate.h"
#import "ICLPayload.h"
#import "ICLPayloadLocalPrivate.h"
#import "WKWebViewPrivate.h"

// Core IRC types
#import "IRCAddressBook.h"
#import "IRCCapability.h"
#import "IRCChannelConfigTypes.h"
#import "IRCChannelMemberList.h"
#import "IRCChannelMemberListPrivate.h"
/* IRCChannel is Swift (Channel). Keep its class declarations out of the
 bridging graph so Swift exports the canonical Objective-C runtime class. */
/* IRCChannelUser / IRCChannelUserMutable are Swift (ChannelUser /
 ChannelUserMutable). Import only the shared rank options here. */
#import "IRCChannelMode.h"
#import "IRCChannelUserTypes.h"
#import "IRCClient.h"
/* IRCClientConfig / IRCClientConfigMutable are Swift. Their shared connection
 configuration enums come from IRCConnectionConfig.h below. */
#import "IRCClientPrivate.h"
#import "IRCColorFormatPrivate.h"
#import "IRCCommandIndexPrivate.h"
#import "IRCConnectionConfig.h"
#import "IRCConnectionErrors.h"
#import "IRCConnectionTypes.h"
#import "IRCHighlightLogEntryPrivate.h"
#import "IRCHighlightMatchCondition.h"
#import "IRCISupportInfo.h"
#import "IRCISupportInfoPrivate.h"
#import "IRCPrefix.h"
#import "RCMConnectionManagerProtocol.h"
/* TDCFileTransferDialogSocket and its delegate/error types are Swift. Keep
 their Objective-C declarations out of the bridging graph. */
#import "TLOLinkParser.h"
/* IRCMessage / IRCMessageMutable are Swift (Message / MessageMutable).
 Keep IRCMessage.h out of this bridging graph. Plugin concrete objects are
 implemented by THOPluginDispatcherSupport.swift for Objective-C callers. */
#import "IRCMessageBatchPrivate.h"
#import "IRCNetworkList.h"
#import "IRCSTSPolicy.h"
#import "IRCServerPrivate.h"
/* IRCUser / IRCUserMutable are Swift (User / UserMutable). Keep IRCUser.h
 out of this bridging graph. */
#import "IRCTreeItemPrivate.h"
#import "IRCTypingTrackerPrivate.h"
#import "IRCWorld.h"
#import "IRCWorldPrivate.h"

// Application and preferences
#import "BuildConfig.h"
#import "TPCApplicationInfo.h"
#import "TPCPathInfo.h"
#import "TPCPathInfoPrivate.h"
#import "TPCPreferencesLocal.h"
#import "TPCPreferencesLocalPrivate.h"
#import "TPCPreferencesReload.h"
#import "TPCPreferencesUserDefaults.h"
#import "TPCPreferencesUserDefaultsMigrationPrivate.h"
#import "TPCResourceManager.h"
#import "TPCResourceManagerPrivate.h"
/* TPCTheme / TPCThemeSettings are Swift. Import only their shared enum and
 value declarations so Swift exports the canonical Objective-C classes. */
#import "TPCThemeTypes.h"
/* TPCThemeController is Swift; keep its Objective-C class declarations out of
 the bridging graph so Swift exports the canonical runtime class. */
/* TXMasterController is Swift (MasterController). Keep TXMasterController.h
 out of this bridging graph. */
#import "TLOTimer.h"

// AppKitSupport
#import "TVCAutoExpandingTextField.h"

// InputHandling
#import "THOPluginItemSupportedFeature.h"
#import "THOPluginProtocol.h"
#import "THOPluginProtocolPrivate.h"
#import "TLOInputHistoryPrivate.h"
#import "TLOKeyEventHandler.h"
#import "TLONicknameCompletionStatusPrivate.h"

#import "ICLInlineContentProtocol.h"
#import "TLOpenLink.h"
#import "TPCPreferencesImportExport.h"
#import "TPCPreferencesImportExportPrivate.h"
#import "TVCLogControllerInlineMediaServicePrivate.h"
#import "TVCLogPolicyPrivate.h"
#import "TVCLogViewPrivate.h"
/* TVCMainWindow is implemented in Swift. Keep its class and category
 declarations out of the bridging graph. */

// Networking and notifications
#import "OELReachability.h"
#import "TDCAddressBookSheetPrivate.h"
#import "TDCChannelBanListSheetPrivate.h"
#import "TDCChannelInviteSheetPrivate.h"
#import "TDCChannelModifyModesSheetPrivate.h"
#import "TDCChannelModifyTopicSheetPrivate.h"
#import "TDCChannelSpotlightSearchResultPrivate.h"
/* TDCFileTransferDialogTransferController is implemented in Swift. */
#import "TDCFileTransferDialogTypes.h"
#import "TDCHighlightEntrySheetPrivate.h"
#import "TDCInputPrompt.h"
#import "TDCNicknameColorSheetPrivate.h"
#import "TDCPreferencesUserStyleSheetPrivate.h"
#import "TDCReactionPopoverControllerPrivate.h"
#import "TDCServerChangeNicknameSheetPrivate.h"
#import "TDCServerHighlightListSheetPrivate.h"
#import "TDCSheetBase.h"
#import "TLOFileLoggerPrivate.h"
#import "TLOInternetAddressLookup.h"
#import "TLONotificationConfigurationPrivate.h"
#import "TLONotificationControllerPrivate.h"
#import "TLOSpeechSynthesizerEnginePrivate.h"
#import "TVCDockIconPrivate.h"
#import "TVCErrorMessagePopoverControllerPrivate.h"
#import "TVCErrorMessagePopoverPrivate.h"
#import "TVCMainWindowLoadingScreen.h"
#import "TVCValidatedComboBox.h"
#import "TVCValidatedTextField.h"
#import "TXAppearance.h"
#import "TXAppearancePrivate.h"
#import "TXApplicationPrivate.h"
#import "TXMenuController.h"
#import "TXMenuControllerPrivate.h"
#import "TXWindowControllerPrivate.h"
/* TVCAppearance / TVCApplicationAppearance are Swift (ViewAppearance /
 ApplicationAppearance). Keep TVCAppearance.h out of this bridging graph. */
#import "IRCUserNicknameColorStyleGeneratorPrivate.h"

// Text and presentation
#import "HLSHistoricLogProtocol.h"
#import "TVCLogControllerOperationQueuePrivate.h"
/* TVCLogController and its print-operation context are Swift. Keep their
 Objective-C class declarations out of the bridging graph. */
#import "TVCLogLine.h"
#import "TVCLogLinePrivate.h"
#import "TVCLogLineXPCPrivate.h"
/* TVCLogRenderer is Swift. Its Objective-C compatibility declaration remains
 available to unmigrated callers without entering Swift's bridging graph. */
#import "TVCMemberList.h"
#import "TVCMemberListPrivate.h"
/* TVCServerList is Swift (ServerList). Keep TVCServerList.h out of this
 bridging graph; cell private APIs stay available for drawing. */
/* TVCServerListCell* are Swift (ServerListCell*). Keep Private out of bridging.
 */
#import "NSTableVIewHelperPrivate.h"
#import "TVCLogViewInternalWK2.h"

/* TDCPreferencesController is Swift. Its compatibility declaration remains
 available to unmigrated Objective-C callers without entering this bridge. */

/* TDCFileTransferDialog is Swift and exports its Objective-C runtime class. */
