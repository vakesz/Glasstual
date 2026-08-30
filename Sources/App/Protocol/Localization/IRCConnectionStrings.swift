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

nonisolated enum IRCConnectionStrings { // nonisolated: value
	static var noConfiguredServers: String {
		String(localized: .IRC.thereAreNoServersConfigured)
	}

	static var reconnecting: String {
		String(localized: .IRC.miscellaneousMessagesRelatedReconnecting)
	}

	static var retrying: String {
		String(localized: .IRC.miscellaneousMessagesRelatedRetrying)
	}

	static var legacyIPv4PreferenceNotice: String {
		String(localized: .IRC.pleaseTakeNoticeThePreferenceLabeled)
	}

	static var defaultAwayMessage: String {
		String(localized: .IRC.beBackLater)
	}

	static var serviceClosedUnexpectedly: String {
		String(localized: .IRC.connectionServiceClosedUnexpectedly)
	}

	static var serverClosedReadStream: String {
		String(localized: .IRC.serverClosedReadStream)
	}

	static var hostConnectionEstablished: String {
		String(localized: .IRC.connectionToHostEstablished)
	}

	static var autojoinDelayedForIdentification: String {
		String(localized: .IRC.joiningChannelsHasBeenDelayedBecause)
	}

	static var reconnectingToProxy: String {
		String(localized: .IRC.reconnectingToProxyToRebuildInternal)
	}

	static var labeledResponseNotAcknowledged: String {
		String(localized: .IRC.serverDidNotAcknowledgeThisMessage)
	}

	static func disconnectReason(for mode: IRCClientDisconnectMode) -> String {
		switch mode {
		case .normal: String(localized: .IRC.miscellaneousMessagesRelatedDisconnected)
		case .computerSleep: String(localized: .IRC.disconnectedForSleepMode)
		case .badCertificate: String(localized: .IRC.disconnectedFromServerBecause)
		case .serverRedirect: String(localized: .IRC.disconnectedForServerRedirect)
		case .reachabilityChange: String(localized: .IRC.disconnectedFromServerBecauseTheInternet)
		@unknown default: String(localized: .IRC.miscellaneousMessagesRelatedDisconnected)
		}
	}

	static func socksProxy(host: String, port: UInt16) -> String {
		String(localized: .IRC.connectingUsingSocks5ProxyOnPort(host, String(port)))
	}

	static func httpProxy(host: String, port: UInt16) -> String {
		String(localized: .IRC.connectingUsingHttpProxyOnPort(host, String(port)))
	}

	static func cipherSuite(protocolName: String, cipherName: String, deprecated: Bool) -> String {
		if deprecated {
			return String(localized: .IRC.withTheCipherSuite4Deprecated(protocolName, cipherName))
		}

		return String(localized: .IRC.withTheCipherSuite(protocolName, cipherName))
	}

	static func secured(using description: String) -> String {
		String(localized: .IRC.connectionSecuredUsing(description))
	}

	static func hostConnectionEstablished(address: String) -> String {
		String(localized: .IRC.connectionToHostAtEstablished(address))
	}

	static func connecting(host: String, port: UInt16) -> String {
		String(localized: .IRC.connectingToOnPort(host, String(port)))
	}

	static func delayedAutoConnect(seconds: UInt) -> String {
		String(localized: .IRC.delayingAutoConnectForSeconds(seconds))
	}

	static func timeout(minutes: Double) -> String {
		String(localized: .IRC.minutesHaveElapsedSinceLastResponse(Float(minutes)))
	}

	static func possibleTimeout(minutes: Double) -> String {
		String(localized: .IRC.minutesHaveElapsedSinceLastResponseFromThis(Float(minutes)))
	}
}

nonisolated enum IRCTransportSecurityStrings { // nonisolated: value
	static var policyWithdrawn: String {
		String(localized: .IRC.serverWithdrewItsStrictTransportSecurity)
	}

	static var malformedSCRAMMessage: String {
		String(localized: .IRC.saslScramAuthenticationFailedTheServer)
	}

	static func enforcedPolicy(port: UInt16) -> String {
		String(localized: .IRC.strictTransportSecurityPolicy(String(port)))
	}

	static func offeredPolicy(port: UInt16) -> String {
		String(localized: .IRC.serverOffersStrictTransportSecurityReconnecting(String(port)))
	}

	static func storedPolicy(port: UInt16) -> String {
		String(localized: .IRC.storedAStrictTransportSecurityPolicy(String(port)))
	}

	static func scramFailure(_ description: String) -> String {
		String(localized: .IRC.saslScramAuthenticationFailed(description))
	}

	static var scramServerSignatureMissing: String {
		String(localized: .IRC.saslScramAuthenticationFailedTheServerDidNot)
	}

	static var saslPayloadTooLarge: String {
		String(localized: .IRC.saslAuthenticationFailedTheServerSent)
	}
}

nonisolated enum IRCTransportStrings { // nonisolated: value
	static var notConnected: String {
		String(localized: .IRC.failedToSendDataToServer)
	}

	static var messagesUnavailableInWindow: String {
		String(localized: .IRC.messagesCannotBeSent)
	}

	static var confirmLargeMessage: String {
		String(localized: .IRC.areYouSureYouWant)
	}

	static var largeMessageWarning: String {
		String(localized: .IRC.messageThatYouAreSending)
	}

	static var operatorMessageUnsupported: String {
		String(localized: .IRC.cannotSendOperatorMessageBecause)
	}

	static func connectCommand(target: String, redactedMessage: String) -> String {
		String(localized: .IRC.connectCommandSent(target, redactedMessage))
	}
}
