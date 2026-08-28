/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

public nonisolated extension Preferences {
	/// The identity a new connection is seeded with.
	nonisolated enum Identity {
		public static let nickname = PreferenceKey("DefaultIdentity -> Nickname", default: "Guest")
		public static let awayNickname = PreferenceKey("DefaultIdentity -> AwayNickname", default: "")
		public static let username = PreferenceKey("DefaultIdentity -> Username", default: "glasstual")
		public static let realName = PreferenceKey("DefaultIdentity -> Realname", default: "Glasstual User")

		public static let ctcpVersionMasquerade = PreferenceKey(
			"ApplicationCTCPVersionMasquerade",
			default: "",
			traits: .unregistered
		)

		public static let onboardingCompleted = PreferenceKey("Onboarding -> Completed", default: false)

		static let all: [any AnyPreferenceKey] = [
			nickname, awayNickname, username, realName, ctcpVersionMasquerade, onboardingCompleted,
		]
	}
}

// MARK: - Connection

public nonisolated extension Preferences {
	/// Connecting, joining, and the behaviour of the connection itself.
	nonisolated enum Connection {
		public static let autojoinOnInvite = PreferenceKey("AutojoinChannelOnInvite", default: false)

		public static let autojoinDelayAfterIdentification = PreferenceKey(
			"AutojoinDelayAfterIdentification",
			default: 0.0
		)

		public static let autojoinDelayBetweenChannelJoins = PreferenceKey(
			"AutojoinDelayBetweenChannelJoins",
			default: 2.2
		)

		public static let autojoinMaximumChannelJoins = PreferenceKey(
			"AutojoinMaximumChannelJoinCount",
			default: UInt(2)
		)

		public static let disconnectOnSleep = PreferenceKey("AutomaticallyDisconnectForSleepMode", default: true)
		public static let awayOnScreenSleep = PreferenceKey("SetAwayOnScreenSleep", default: false)
		public static let preferModernCiphers = PreferenceKey("PreferModernCiphers", default: false)
		public static let displayServerMOTD = PreferenceKey("DisplayServerMessageOfTheDayOnConnect", default: true)
		public static let rejoinOnKick = PreferenceKey("RejoinChannelOnLocalKick", default: false)
		public static let sendTypingNotifications = PreferenceKey("SendTypingNotifications", default: true)
		public static let confirmQuit = PreferenceKey("ConfirmApplicationQuit", default: true)

		public static let echoMessageCapability = PreferenceKey(
			"IRC -> Enable echo-message Capability",
			default: false
		)

		public static let stsPolicies = UntypedPreferenceKey(
			"IRC -> STS Policies",
			default: .emptyDictionary,
			traits: .excludedFromExport
		)

		public static let clientList = UntypedPreferenceKey(IRCWorldClientListDefaultsKey)

		static let all: [any AnyPreferenceKey] = [
			autojoinOnInvite, autojoinDelayAfterIdentification, autojoinDelayBetweenChannelJoins,
			autojoinMaximumChannelJoins, disconnectOnSleep, awayOnScreenSleep, preferModernCiphers,
			displayServerMOTD, rejoinOnKick, sendTypingNotifications, confirmQuit, echoMessageCapability,
			stsPolicies, clientList,
		]
	}
}

// MARK: - Commands

public nonisolated extension Preferences {
	/// Command defaults and the "apply to all connections" switches.
	nonisolated enum Commands {
		public static let amsgAllConnections = PreferenceKey(
			"ApplyCommandToAllConnections -> amsg",
			default: false
		)

		public static let awayAllConnections = PreferenceKey(
			"ApplyCommandToAllConnections -> away",
			default: false
		)

		public static let clearAllConnections = PreferenceKey(
			"ApplyCommandToAllConnections -> clearall",
			default: true
		)

		public static let nickAllConnections = PreferenceKey(
			"ApplyCommandToAllConnections -> nick",
			default: false
		)

		public static let kickMessage = PreferenceKey(
			"ChannelOperatorDefaultLocalization -> Kick Reason",
			default: "Your behavior is not conducive to the desired environment."
		)

		public static let irCopGlineMessage = PreferenceKey(
			"IRCopDefaultLocalizaiton -> G:Line Reason",
			default: "35d Your behavior is not conducive to the desired environment."
		)

		public static let irCopKillMessage = PreferenceKey(
			"IRCopDefaultLocalizaiton -> Kill Reason",
			default: "Your behavior is not conducive to the desired environment."
		)

		public static let irCopShunMessage = PreferenceKey(
			"IRCopDefaultLocalizaiton -> Shun Reason",
			default: "1d Shunned."
		)

		public static let banFormat = PreferenceKey(
			"DefaultBanCommandHostmaskFormat",
			default: TXHostmaskBanFormat.whainn
		)

		public static let noticeDestination = PreferenceKey(
			"DestinationOfNonserverNotices",
			default: TXNoticeSendLocation.serverConsole
		)

		public static let giveFocusOnMessageCommand = PreferenceKey(
			"FocusSelectionOnMessageCommandExecution",
			default: true
		)

		public static let developerMode = PreferenceKey("GlasstualDeveloperEnvironment", default: false)

		static let all: [any AnyPreferenceKey] = [
			amsgAllConnections, awayAllConnections, clearAllConnections, nickAllConnections,
			kickMessage, irCopGlineMessage, irCopKillMessage, irCopShunMessage, banFormat,
			noticeDestination, giveFocusOnMessageCommand, developerMode,
		]
	}
}
