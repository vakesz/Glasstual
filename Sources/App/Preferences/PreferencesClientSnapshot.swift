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

		snapshot.autojoinDelayAfterIdentification = Preferences.Connection.autojoinDelayAfterIdentification.value
		snapshot.autojoinDelayBetweenChannelJoins = Preferences.Connection.autojoinDelayBetweenChannelJoins.value
		snapshot.autojoinMaximumChannelJoins = Preferences.Connection.autojoinMaximumChannelJoins.value
		snapshot.autojoinOnInvite = Preferences.Connection.autojoinOnInvite.value
		snapshot.rejoinOnKick = Preferences.Connection.rejoinOnKick.value
		snapshot.appNapEnabled = TextualPreferences.appNapEnabled()
		snapshot.preferModernCiphers = Preferences.Connection.preferModernCiphers.value
		snapshot.disconnectOnSleep = Preferences.Connection.disconnectOnSleep.value
		snapshot.awayOnScreenSleep = Preferences.Connection.awayOnScreenSleep.value
		snapshot.enableEchoMessageCapability = TextualPreferences.enableEchoMessageCapability()
		snapshot.requestChatHistory = Preferences.Connection.requestChatHistory.value
		snapshot.synchronizeReadMarkers = Preferences.Connection.synchronizeReadMarkers.value
		snapshot.rememberServerListQueryStates = Preferences.Appearance.rememberQueryStates.value
		snapshot.trackUserAwayStatusMaximumChannelSize = Preferences.Appearance
			.trackUserAwayStatusMaximumChannelSize
			.value

		snapshot.removeAllFormatting = Preferences.Messages.removeAllFormatting.value
		snapshot.showJoinLeave = Preferences.Messages.showJoinLeave.value
		snapshot.displayServerMOTD = Preferences.Connection.displayServerMOTD.value
		snapshot.replyToCTCPRequests = Preferences.Messages.replyToCTCPRequests.value
		snapshot.masqueradeCTCPVersion = Preferences.Identity.ctcpVersionMasquerade.storedValue
		snapshot.locationToSendNotices = Preferences.Commands.noticeDestination.value
		snapshot.sendTypingNotifications = Preferences.Connection.sendTypingNotifications.value
		snapshot.displayTypingNotifications = Preferences.Connection.displayTypingNotifications.value
		snapshot.giveFocusOnMessageCommand = Preferences.Commands.giveFocusOnMessageCommand.value
		snapshot.autoAddScrollbackMark = Preferences.Messages.autoAddScrollbackMark.value
		snapshot.defaultKickMessage = Preferences.Commands.kickMessage.value
		snapshot.irCopDefaultKillMessage = Preferences.Commands.irCopKillMessage.value
		snapshot.banFormat = Preferences.Commands.banFormat.value

		snapshot.amsgAllConnections = Preferences.Commands.amsgAllConnections.value
		snapshot.awayAllConnections = Preferences.Commands.awayAllConnections.value
		snapshot.nickAllConnections = Preferences.Commands.nickAllConnections.value
		snapshot.clearAllConnections = Preferences.Commands.clearAllConnections.value

		snapshot.displayPublicMessageCountOnDockBadge = Preferences.Notifications
			.publicMessageCountOnDockBadge
			.value
		snapshot.memberListSortFavorsServerStaff = Preferences.Appearance.memberListSortFavorsServerStaff.detachedValue
		snapshot.disableNicknameColorHashing = Preferences.Messages.disableNicknameColorHashing.detachedValue
		snapshot.showInlineMedia = Preferences.Messages.showInlineMedia.detachedValue
		snapshot.soundIsMuted = Preferences.Notifications.soundIsMuted.value

		snapshot.highlightCurrentNickname = Preferences.Highlights.trackLocalNickname.value
		snapshot.highlightMatchingMethod = Preferences.Highlights.matchingMethod.detachedValue
		snapshot.highlightMatchKeywords = TextualPreferences.highlightMatchKeywords() ?? []
		snapshot.highlightExcludeKeywords = TextualPreferences.highlightExcludeKeywords() ?? []
		snapshot.logHighlights = Preferences.Logging.logHighlights.value

		snapshot.logToDiskIsEnabled = TextualPreferences.logToDiskIsEnabled()
		snapshot.developerModeEnabled = Preferences.Commands.developerMode.value
		snapshot.fileTransferRequestReplyAction = Preferences.FileTransfers.requestReplyAction.value
		snapshot.fileTransferPortRangeStart = Preferences.FileTransfers.portRangeStart.value
		snapshot.fileTransferPortRangeEnd = Preferences.FileTransfers.portRangeEnd.value
		snapshot.fileTransferIPAddressInterfaceName = Preferences.FileTransfers.ipAddressInterfaceName.storedValue

		return snapshot
	}
}
