/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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

import Foundation

public enum TXMenuMemberAction: Int, CaseIterable {
	case addIgnore = 0
	case removeIgnore = 1
	case modifyIgnore = 2
	case memberListDoubleClick = 3
	case channelViewDoubleClick = 4
	case insertNickname = 5
	case whois = 6
	case privateMessage = 7
	case ctcpPing = 8
	case ctcpFinger = 9
	case ctcpTime = 10
	case ctcpVersion = 11
	case ctcpUserinfo = 12
	case ctcpClientInfo = 13
	case giveOp = 14
	case takeOp = 15
	case giveHalfop = 16
	case takeHalfop = 17
	case giveVoice = 18
	case takeVoice = 19
	case kick = 20
	case ban = 21
	case kickban = 22
	case kill = 23
	case gline = 24
	case shun = 25
	case setVhost = 26
	case sendFile = 27
	case changeColor = 28
}

public enum TXMenuEditingAction: Int, CaseIterable {
	case showFindPrompt = 0
	case copy = 1
	case paste = 2
	case print = 3
}

public enum TXMenuChannelViewAction: Int, CaseIterable {
	case reply = 0
	case react = 1
	case reactWithOtherEmoji = 2
	case copyLogAsHTML = 3
	case openWebInspector = 4
	case markScrollback = 5
	case goToScrollbackMarker = 6
	case clearScrollback = 7
	case increaseFontSize = 8
	case decreaseFontSize = 9
	case searchWeb = 10
	case lookUpInDictionary = 11
	case copyURL = 12
}

public enum TXMenuServerChannelAction: Int, CaseIterable {
	case connect = 0
	case connectBypassingProxy = 1
	case disconnect = 2
	case cancelReconnection = 3
	case showChannelList = 4
	case addServer = 5
	case duplicateServer = 6
	case deleteServer = 7
	case joinChannel = 8
	case leaveChannel = 9
	case addChannel = 10
	case deleteChannel = 11
	case copyUniqueIdentifier = 12
	case joinClickedChannel = 13
	case empty = 14
}

public enum TXMenuSupportAction: Int, CaseIterable {
	case openLogLocation = 0
	case openChannelLogs = 1
	case openAcknowledgements = 2
	case contactSupport = 3
	case connectToHelpChannel = 4
	case connectToTestingChannel = 5
}

public enum TXMenuIRCAction: Int, CaseIterable {
	case showBanList = 0
	case showBanExceptionList = 1
	case showInviteExceptionList = 2
	case showQuietList = 3
	case toggleModerationMode = 4
	case toggleInviteMode = 5
}

public enum TXMenuWindowAction: Int, CaseIterable {
	case close = 0
	case showMainWindow = 1
	case centerMainWindow = 2
	case resetMainWindowFrame = 3
	case sortChannelList = 4
	case markAllAsRead = 5
	case importPreferences = 6
	case exportPreferences = 7
	case toggleNotificationSounds = 8
	case toggleNotifications = 9
	case resetAppearance = 10
	case toggleAppearance = 11
	case toggleServerList = 12
	case toggleMemberList = 13
	case reloadTheme = 14
	case toggleDeveloperMode = 15
	case resetSuppressedWarnings = 16
}

public enum TXMenuDialogAction: Int, CaseIterable {
	case showChannelProperties = 0
	case sendInvite = 1
	case showAddressBook = 2
	case showOnboarding = 3
	case showAbout = 4
	case showServerProperties = 5
	case showServerHighlightList = 6
	case showChannelTopic = 7
	case showChannelModes = 8
	case showChannelSpotlight = 9
	case showChangeNickname = 10
	case showPreferences = 11
	case showNotificationPreferences = 12
	case showStylePreferences = 13
	case showHiddenPreferences = 14
}
