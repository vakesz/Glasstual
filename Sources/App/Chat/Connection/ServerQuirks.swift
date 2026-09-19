// Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The strings that identify a particular server or bouncer on the wire.
///
/// IRC has no handshake that names the software on the other end, so
/// recognising one means matching a string it sends. Those strings are
/// gathered here rather than repeated at each site that tests for one.
nonisolated enum ServerQuirks {
	/// ZNC, the bouncer Glasstual has specific support for.
	enum ZNC {
		/// The server name ZNC introduces itself with.
		static let serverName = "irc.znc.in"

		/// The sender ZNC puts on its own out-of-band messages.
		static let messageSender = "znc.in"

		/// ZNC exposes each of its modules as a user whose nickname carries
		/// this prefix.
		static let modulePrefix = "*"

		static let playbackModule = "playback"
		static let certificateInfoModule = "tlsinfo"

		static let playbackBatchType = "znc.in/playback"
		static let certificateInfoBatchType = "znc.in/tlsinfo"

		/// The command that asks the `tlsinfo` module for the peer chain.
		static let sendCertificateChainCommand = "send-data"

		static func nickname(forModuleNamed module: String) -> String {
			"\(modulePrefix)\(module)"
		}
	}

	/// The IRCv3 `chathistory` batch, which is not vendor-specific but is
	/// matched by name in the same places the ZNC batches are.
	static let chatHistoryBatchType = "chathistory"

	/// Twitch speaks a dialect of IRC that omits much of what the session
	/// expects, and the only way to know is the address.
	static let twitchAddressSuffix = ".twitch.tv"

	/// Where a network's services expect the account password.
	enum Services {
		/// DALnet refuses an `IDENTIFY` sent to a bare `NickServ`, so the
		/// message names the services server as well.
		static let dalNetAddressSuffix = ".dal.net"
		static let dalNetNickServTarget = "NickServ@services.dal.net"

		/// The service networks that use UserServ take a `login` naming the
		/// account instead of NickServ's `IDENTIFY`.
		static let userServTarget = "userserv"

		static let nickServ = "NickServ"
		static let chanServ = "ChanServ"
	}

	/// A bouncer or proxy announcing that the far side came up. The sender name
	/// and the text are both conventions, not protocol, and the text is
	/// English.
	enum Proxy {
		static let nicknameSuffix = ".proxy"
		static let connectedMessage = "Connected to server"
	}

	/// The server-side reasons for an ERROR that means "do not reconnect".
	/// These are English strings that servers happen to agree on.
	enum LinkClosed {
		static let prefix = "Closing Link:"
		static let excessFlood = "(Excess Flood)"
		static let sendQueueExceeded = "(Max SendQ exceeded)"
	}

	/// The WHOX token the session marks its own WHO requests with, and matches the
	/// replies against: the request and the reply carry the same number.
	static let whoxToken = "152"
}

extension ServerSession {
	var isBrokenIRCdKnownAsTwitch: Bool {
		serverAddress?.hasSuffix(ServerQuirks.twitchAddressSuffix) ?? false
	}
}
