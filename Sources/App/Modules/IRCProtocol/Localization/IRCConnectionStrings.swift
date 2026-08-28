/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

nonisolated enum IRCConnectionStrings {
	static var noConfiguredServers: String {
		String(localized: .IRC.iaa0U)
	}

	static var reconnecting: String {
		String(localized: .IRC.xxbY2)
	}

	static var retrying: String {
		String(localized: .IRC.ky336)
	}

	static var legacyIPv4PreferenceNotice: String {
		String(localized: .IRC.w05Ph)
	}

	static var defaultAwayMessage: String {
		String(localized: .IRC.xogIn)
	}

	static var serviceClosedUnexpectedly: String {
		String(localized: .IRC.vdyJk)
	}

	static var serverClosedReadStream: String {
		String(localized: .IRC._5H5Sl)
	}

	static var hostConnectionEstablished: String {
		String(localized: .IRC._4VtOw)
	}

	static var autojoinDelayedForIdentification: String {
		String(localized: .IRC.r5HFj)
	}

	static var reconnectingToProxy: String {
		String(localized: .IRC._5I4Qq)
	}

	static var labeledResponseNotAcknowledged: String {
		String(localized: .IRC.lblTo)
	}

	static func disconnectReason(for mode: IRCClientDisconnectMode) -> String {
		switch mode {
		case .normal: String(localized: .IRC._9B410)
		case .computerSleep: String(localized: .IRC.drgB7)
		case .badCertificate: String(localized: .IRC.zroBg)
		case .serverRedirect: String(localized: .IRC.wclPo)
		case .reachabilityChange: String(localized: .IRC.isxFi)
		@unknown default: String(localized: .IRC._9B410)
		}
	}

	static func socksProxy(host: String, port: UInt16) -> String {
		IRCLegacyFormat.socksProxy.format(host, port)
	}

	static func httpProxy(host: String, port: UInt16) -> String {
		IRCLegacyFormat.httpProxy.format(host, port)
	}

	static func cipherSuite(protocolName: String, cipherName: String, deprecated: Bool) -> String {
		if deprecated {
			return String(localized: .IRC.xwjXy(protocolName, cipherName))
		}

		return String(localized: .IRC.uyz4R(protocolName, cipherName))
	}

	static func secured(using description: String) -> String {
		String(localized: .IRC.ex4F8(description))
	}

	static func hostConnectionEstablished(address: String) -> String {
		String(localized: .IRC.l21P7(address))
	}

	static func connecting(host: String, port: UInt16) -> String {
		IRCLegacyFormat.serverConnection.format(host, port)
	}

	static func delayedAutoConnect(seconds: UInt) -> String {
		String(localized: .IRC._3S6E6(seconds))
	}

	static func timeout(minutes: Double) -> String {
		String(localized: .IRC.bpsLa(Float(minutes)))
	}

	static func possibleTimeout(minutes: Double) -> String {
		String(localized: .IRC.gzo54(Float(minutes)))
	}
}

nonisolated enum IRCTransportSecurityStrings {
	static var policyWithdrawn: String {
		String(localized: .IRC.stsP4)
	}

	static var malformedSCRAMMessage: String {
		String(localized: .IRC.stsSc1)
	}

	static func enforcedPolicy(port: UInt16) -> String {
		IRCLegacyFormat.enforcedStrictTransportSecurity.format(port)
	}

	static func offeredPolicy(port: UInt16) -> String {
		IRCLegacyFormat.offeredStrictTransportSecurity.format(port)
	}

	static func storedPolicy(port: UInt16) -> String {
		IRCLegacyFormat.storedStrictTransportSecurity.format(port)
	}

	static func scramFailure(_ description: String) -> String {
		String(localized: .IRC.stsSc2(description))
	}

	static var scramServerSignatureMissing: String {
		String(localized: .IRC.stsSc3)
	}

	static var saslPayloadTooLarge: String {
		String(localized: .IRC.stsSc4)
	}
}

nonisolated enum IRCTransportStrings {
	static var notConnected: String {
		String(localized: .IRC._6Rj2R)
	}

	static var messagesUnavailableInWindow: String {
		String(localized: .IRC.z2RSd)
	}

	static var confirmLargeMessage: String {
		String(localized: .IRC.lql8I)
	}

	static var largeMessageWarning: String {
		String(localized: .IRC.u4C7I)
	}

	static var operatorMessageUnsupported: String {
		String(localized: .IRC._54LH7)
	}

	static func connectCommand(target: String, redactedMessage: String) -> String {
		String(localized: .IRC.ccs1A(target, redactedMessage))
	}
}
