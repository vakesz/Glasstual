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

@objc public enum IRCClientConnectMode: UInt, Sendable {
	case normal
	case retry
	case reconnect
}

@objc public enum IRCClientDisconnectMode: UInt, Sendable {
	case normal
	case computerSleep
	case badCertificate
	case reachabilityChange
	case serverRedirect
}

/// Opaque capability identifiers used by the client's negotiated-capability registry.
public nonisolated struct ClientIRCv3SupportedCapability: OptionSet, Hashable, Sendable {
	public let rawValue: UInt

	public init(rawValue: UInt) {
		self.rawValue = rawValue
	}

	public static let awayNotify = Self(rawValue: 1 << 0)
	public static let batch = Self(rawValue: 1 << 1)
	public static let echoMessage = Self(rawValue: 1 << 2)
	public static let isIdentifiedWithSASL = Self(rawValue: 1 << 5)
	public static let isInSASLNegotiation = Self(rawValue: 1 << 6)
	public static let monitorCommand = Self(rawValue: 1 << 7)
	public static let multiPrefix = Self(rawValue: 1 << 8)
	public static let playback = Self(rawValue: 1 << 9)
	public static let serverTime = Self(rawValue: 1 << 10)
	public static let userhostInNames = Self(rawValue: 1 << 11)
	public static let watchCommand = Self(rawValue: 1 << 12)
	public static let zncCertInfoModule = Self(rawValue: 1 << 13)
	public static let zncSelfMessage = Self(rawValue: 1 << 14)
	public static let changeHost = Self(rawValue: 1 << 15)
	public static let messageTags = Self(rawValue: 1 << 16)
	public static let capNotify = Self(rawValue: 1 << 17)
	public static let standardReplies = Self(rawValue: 1 << 18)
	public static let chatHistory = Self(rawValue: 1 << 19)
	public static let readMarker = Self(rawValue: 1 << 20)
	public static let labeledResponse = Self(rawValue: 1 << 21)
	/// `sasl`, as opposed to the mechanism-specific SASL bits.
	public static let saslGeneric = Self(rawValue: 1 << 22)
	public static let zncServerTime = Self(rawValue: 1 << 25)
	public static let zncServerTimeISO = Self(rawValue: 1 << 26)
	public static let zncPlaybackModule = Self(rawValue: 1 << 27)
	public static let accountNotify = Self(rawValue: 1 << 28)
	public static let extendedJoin = Self(rawValue: 1 << 29)
	public static let accountTag = Self(rawValue: 1 << 30)
	public static let setName = Self(rawValue: 1 << 31)
	public static let inviteNotify = Self(rawValue: 1 << 32)
	public static let extendedMonitor = Self(rawValue: 1 << 33)
	public static let preAway = Self(rawValue: 1 << 34)
}
