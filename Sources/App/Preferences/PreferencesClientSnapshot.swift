/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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

/** Fills the IRC layer's preference snapshot from the defaults store.

 This lives with the preferences rather than with the snapshot so that the
 connection code declares what it needs and never reads the store itself. */
extension ClientPreferences {
	/// Reads the shared defaults store once, on the main actor that owns it.
	/// The result is a `Sendable` value the connection layer keeps.
	@MainActor
	static func current() -> ClientPreferences {
		var snapshot = ClientPreferences()

		snapshot.autojoinDelayAfterIdentification = TextualPreferences.autojoinDelayAfterIdentification()
		snapshot.autojoinDelayBetweenChannelJoins = TextualPreferences.autojoinDelayBetweenChannelJoins()
		snapshot.autojoinMaximumChannelJoins = TextualPreferences.autojoinMaximumChannelJoins()
		snapshot.autojoinOnInvite = TextualPreferences.autoJoinOnInvite()
		snapshot.rejoinOnKick = TextualPreferences.rejoinOnKick()
		snapshot.appNapEnabled = TextualPreferences.appNapEnabled()
		snapshot.preferModernCiphers = TextualPreferences.preferModernCiphers()
		snapshot.disconnectOnSleep = TextualPreferences.disconnectOnSleep()
		snapshot.awayOnScreenSleep = TextualPreferences.setAwayOnScreenSleep()
		snapshot.enableEchoMessageCapability = TextualPreferences.enableEchoMessageCapability()
		snapshot.rememberServerListQueryStates = TextualPreferences.rememberServerListQueryStates()
		snapshot.trackUserAwayStatusMaximumChannelSize = TextualPreferences
			.trackUserAwayStatusMaximumChannelSize()

		snapshot.removeAllFormatting = TextualPreferences.removeAllFormatting()
		snapshot.showJoinLeave = TextualPreferences.showJoinLeave()
		snapshot.displayServerMOTD = TextualPreferences.displayServerMOTD()
		snapshot.replyToCTCPRequests = TextualPreferences.replyToCTCPRequests()
		snapshot.masqueradeCTCPVersion = TextualPreferences.masqueradeCTCPVersion()
		snapshot.locationToSendNotices = TextualPreferences.locationToSendNotices()
		snapshot.sendTypingNotifications = TextualPreferences.sendTypingNotifications()
		snapshot.giveFocusOnMessageCommand = TextualPreferences.giveFocusOnMessageCommand()
		snapshot.autoAddScrollbackMark = TextualPreferences.autoAddScrollbackMark()
		snapshot.defaultKickMessage = TextualPreferences.defaultKickMessage()
		snapshot.irCopDefaultKillMessage = TextualPreferences.irCopDefaultKillMessage()
		snapshot.banFormat = TextualPreferences.banFormat()

		snapshot.amsgAllConnections = TextualPreferences.amsgAllConnections()
		snapshot.awayAllConnections = TextualPreferences.awayAllConnections()
		snapshot.nickAllConnections = TextualPreferences.nickAllConnections()
		snapshot.clearAllConnections = TextualPreferences.clearAllConnections()

		snapshot.displayPublicMessageCountOnDockBadge = TextualPreferences
			.displayPublicMessageCountOnDockBadge()
		snapshot.memberListSortFavorsServerStaff = TextualPreferences.memberListSortFavorsServerStaff()
		snapshot.disableNicknameColorHashing = TextualPreferences.disableNicknameColorHashing()
		snapshot.showInlineMedia = TextualPreferences.showInlineMedia()
		snapshot.themeNicknameFormat = TextualPreferences.themeNicknameFormat()
		snapshot.themeNicknameFormatDefault = TextualPreferences.themeNicknameFormatDefault()
		snapshot.soundIsMuted = TextualPreferences.soundIsMuted()

		snapshot.highlightCurrentNickname = TextualPreferences.highlightCurrentNickname()
		snapshot.highlightMatchingMethod = TextualPreferences.highlightMatchingMethod()
		snapshot.highlightMatchKeywords = TextualPreferences.highlightMatchKeywords() ?? []
		snapshot.highlightExcludeKeywords = TextualPreferences.highlightExcludeKeywords() ?? []
		snapshot.logHighlights = TextualPreferences.logHighlights()

		snapshot.logToDiskIsEnabled = TextualPreferences.logToDiskIsEnabled()
		snapshot.developerModeEnabled = TextualPreferences.developerModeEnabled()
		snapshot.fileTransferRequestReplyAction = TextualPreferences.fileTransferRequestReplyAction()
		snapshot.fileTransferPortRangeStart = TextualPreferences.fileTransferPortRangeStart()
		snapshot.fileTransferPortRangeEnd = TextualPreferences.fileTransferPortRangeEnd()
		snapshot.fileTransferIPAddressInterfaceName = TextualPreferences.fileTransferIPAddressInterfaceName()

		return snapshot
	}
}
