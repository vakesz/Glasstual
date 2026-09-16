/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

// MARK: - Identity

nonisolated extension Preferences { // nonisolated: value
	/// The identity a new connection is seeded with.
	enum Identity {
		static let nickname = PreferenceKey("DefaultIdentity -> Nickname", default: "Guest")
		static let awayNickname = PreferenceKey("DefaultIdentity -> AwayNickname", default: "")
		static let username = PreferenceKey("DefaultIdentity -> Username", default: "glasstual")
		static let realName = PreferenceKey("DefaultIdentity -> Realname", default: "Glasstual User")

		static let ctcpVersionMasquerade = PreferenceKey(
			"ApplicationCTCPVersionMasquerade",
			default: "",
			traits: .unregistered
		)

		static let onboardingCompleted = PreferenceKey("Onboarding -> Completed", default: false)

		static let all: [any AnyPreferenceKey] = [
			nickname, awayNickname, username, realName, ctcpVersionMasquerade, onboardingCompleted,
		]
	}
}

// MARK: - Connection

nonisolated extension Preferences { // nonisolated: value
	/// Connecting, joining, and the behaviour of the connection itself.
	enum Connection {
		static let autojoinOnInvite = PreferenceKey("AutojoinChannelOnInvite", default: false)

		static let autojoinDelayAfterIdentification = PreferenceKey(
			"AutojoinDelayAfterIdentification",
			default: 0.0,
			validation: { $0.isFinite && $0 >= 0 && $0 < Double(Int64.max) / 1_000_000_000 }
		)

		static let disconnectOnSleep = PreferenceKey("AutomaticallyDisconnectForSleepMode", default: true)

		/** Holds off idle system sleep while a server is logged in.

		 The stored name is the one the setting had when it belonged to a
		 bundled extension, so the user's choice survives that extension going
		 away. */
		static let preventSleepWhileConnected = PreferenceKey(
			"Private Extension Store -> Caffeine Extension -> Prevent Sleep",
			default: false
		)
		static let awayOnScreenSleep = PreferenceKey("SetAwayOnScreenSleep", default: false)
		static let preferModernCiphers = PreferenceKey("PreferModernCiphers", default: true)
		static let displayServerMOTD = PreferenceKey("DisplayServerMessageOfTheDayOnConnect", default: true)
		static let rejoinOnKick = PreferenceKey("RejoinChannelOnLocalKick", default: false)
		static let sendTypingNotifications = PreferenceKey("SendTypingNotifications", default: true)
		static let displayTypingNotifications = PreferenceKey(
			"IRC -> Display Typing Notifications",
			default: true
		)
		static let confirmQuit = PreferenceKey("ConfirmApplicationQuit", default: true)
		static let requestChatHistory = PreferenceKey(
			"IRC -> Request Chat History",
			default: true
		)
		static let synchronizeReadMarkers = PreferenceKey(
			"IRC -> Synchronize Read Markers",
			default: true
		)

		static let echoMessageCapability = PreferenceKey(
			"IRC -> Enable echo-message Capability",
			default: false
		)

		/** The IRCv3 capabilities the user switched off, by their wire name.

		 Absence is the enabled state, so a capability added to the registry
		 later starts enabled without a migration, and a name left behind by a
		 capability that was removed does nothing. */
		static let disabledCapabilities = PreferenceKey(
			"IRC -> Disabled Capabilities",
			default: [String]()
		)

		static let stsPolicies = UntypedPreferenceKey(
			"IRC -> STS Policies",
			default: .emptyDictionary,
			traits: .excludedFromExport
		)

		static let clientList = UntypedPreferenceKey(worldClientListDefaultsKey)

		static let all: [any AnyPreferenceKey] = [
			autojoinOnInvite, autojoinDelayAfterIdentification, disconnectOnSleep, awayOnScreenSleep,
			preferModernCiphers,
			displayServerMOTD, rejoinOnKick, sendTypingNotifications, displayTypingNotifications,
			confirmQuit, requestChatHistory, synchronizeReadMarkers, echoMessageCapability,
			disabledCapabilities, stsPolicies, clientList, preventSleepWhileConnected,
		]
	}
}

// MARK: - Commands

nonisolated extension Preferences { // nonisolated: value
	/// Command defaults and the "apply to all connections" switches.
	enum Commands {
		static let amsgAllConnections = PreferenceKey(
			"ApplyCommandToAllConnections -> amsg",
			default: false
		)

		static let awayAllConnections = PreferenceKey(
			"ApplyCommandToAllConnections -> away",
			default: false
		)

		static let clearAllConnections = PreferenceKey(
			"ApplyCommandToAllConnections -> clearall",
			default: true
		)

		static let nickAllConnections = PreferenceKey(
			"ApplyCommandToAllConnections -> nick",
			default: false
		)

		static let kickMessage = PreferenceKey(
			"ChannelOperatorDefaultLocalization -> Kick Reason",
			default: "Your behavior is not conducive to the desired environment."
		)

		static let irCopGlineMessage = PreferenceKey(
			"IRCopDefaultLocalizaiton -> G:Line Reason",
			default: "35d Your behavior is not conducive to the desired environment."
		)

		static let irCopKillMessage = PreferenceKey(
			"IRCopDefaultLocalizaiton -> Kill Reason",
			default: "Your behavior is not conducive to the desired environment."
		)

		static let irCopShunMessage = PreferenceKey(
			"IRCopDefaultLocalizaiton -> Shun Reason",
			default: "1d Shunned."
		)

		static let banFormat = PreferenceKey(
			"DefaultBanCommandHostmaskFormat",
			default: HostmaskBanFormat.whainn
		)

		static let noticeDestination = PreferenceKey(
			"DestinationOfNonserverNotices",
			default: NoticeSendLocation.serverConsole
		)

		static let giveFocusOnMessageCommand = PreferenceKey(
			"FocusSelectionOnMessageCommandExecution",
			default: true
		)

		static let developerMode = PreferenceKey("GlasstualDeveloperEnvironment", default: false)

		static let all: [any AnyPreferenceKey] = [
			amsgAllConnections, awayAllConnections, clearAllConnections, nickAllConnections,
			kickMessage, irCopGlineMessage, irCopKillMessage, irCopShunMessage, banFormat,
			noticeDestination, giveFocusOnMessageCommand, developerMode,
		]
	}
}

/** Where a notice that names no channel is shown.

 Stored as the integer it declares; a stored value with no matching case falls
 back to the key's declared default. */
enum NoticeSendLocation: UInt, Sendable {
	case serverConsole
	case selectedChannel
	case query
}

extension NoticeSendLocation: PreferenceEnum {}

/// Which parts of a hostmask a generated ban covers.
enum HostmaskBanFormat: UInt, Sendable {
	case whnin
	case whainn
	case whanni
	case exact
}

extension HostmaskBanFormat: PreferenceEnum {}
