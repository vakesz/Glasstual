/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
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

/// The strings that identify a particular server or bouncer on the wire.
///
/// IRC has no handshake that names the software on the other end, so
/// recognising one means matching a string it sends. Those strings are
/// gathered here rather than repeated at each site that tests for one.
nonisolated enum IRCServerQuirks {
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

	/// Twitch speaks a dialect of IRC that omits much of what the client
	/// expects, and the only way to know is the address.
	static let twitchAddressSuffix = ".twitch.tv"

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

	/// The WHOX token the client tags its own WHO requests with, so it can
	/// recognise the replies to them.
	static let whoxResponseToken = "152"
}
