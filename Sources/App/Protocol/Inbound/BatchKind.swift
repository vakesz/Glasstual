// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What a `BATCH` line's type names, for the types the session treats
 specially.

 The wire spelling stays on ``MessageBatch/batchType``: a type this client does
 not know, or a known one in the spelling the server used, is never rewritten.
 This is a reading of that string, so an unknown type is ``other(_:)`` with its
 text intact. Matching is exact and case-sensitive, as the specifications
 write the names. */
nonisolated enum BatchKind: Sendable, Equatable {
	/// `chathistory`, or `draft/chathistory` as it shipped.
	case chatHistory
	/// `draft/multiline`, or the name it will have once final.
	case multiline
	/// soju's answer to `BOUNCER LISTNETWORKS`.
	case bouncerNetworks
	case netsplit
	case netjoin
	/// A bouncer's replay under the bare name `playback`.
	case playback
	/// ZNC's `znc.in/playback` replay.
	case zncPlayback
	/// ZNC's `znc.in/tlsinfo` certificate listing.
	case zncTLSInfo
	/// `draft/extended-isupport`'s RPL_ISUPPORT batch, or the name it will
	/// have once final.
	case isupport
	/// The list of conversations a `CHATHISTORY TARGETS` request returns.
	case chatHistoryTargets
	case other(String)

	init(wireType: String) {
		switch wireType {
		case "chathistory", "draft/chathistory": self = .chatHistory
		case MultilineLimits.batchType, "multiline": self = .multiline
		case "soju.im/bouncer-networks": self = .bouncerNetworks
		case "netsplit": self = .netsplit
		case "netjoin": self = .netjoin
		case "playback": self = .playback
		case "znc.in/playback": self = .zncPlayback
		case "znc.in/tlsinfo": self = .zncTLSInfo
		case "draft/isupport", "isupport": self = .isupport
		case "draft/chathistory-targets", "chathistory-targets": self = .chatHistoryTargets
		default: self = .other(wireType)
		}
	}

	/// The canonical spelling of a known kind, and the original text of an
	/// unknown one.
	var wireType: String {
		switch self {
		case .chatHistory: "chathistory"
		case .multiline: MultilineLimits.batchType
		case .bouncerNetworks: "soju.im/bouncer-networks"
		case .netsplit: "netsplit"
		case .netjoin: "netjoin"
		case .playback: "playback"
		case .zncPlayback: "znc.in/playback"
		case .zncTLSInfo: "znc.in/tlsinfo"
		case .isupport: "draft/isupport"
		case .chatHistoryTargets: "draft/chathistory-targets"
		case let .other(type): type
		}
	}

	/// A batch whose contents were said before the session asked for them:
	/// `chathistory` (IRCv3) or a bouncer's playback batch (ZNC).
	var isReplay: Bool {
		switch self {
		case .chatHistory, .playback, .zncPlayback: true
		default: false
		}
	}
}
