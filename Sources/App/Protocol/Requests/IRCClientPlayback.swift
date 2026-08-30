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

enum PlaybackRequestPolicy {
	static func command(
		successfulConnects: UInt,
		onlyLatestOnFirstConnect: Bool,
		lastMessageServerTime: TimeInterval
	) -> String {
		let shouldUseTimestamp = (
			successfulConnects > 1 || (successfulConnects == 1 && onlyLatestOnFirstConnect)
		) && lastMessageServerTime > 0

		guard shouldUseTimestamp else { return "play * 0" }
		return String(format: "play * %.0f", lastMessageServerTime)
	}
}

extension IRCClient {
	func clearPlayback(for channel: IRCChannel) {
		guard isCapabilityEnabled(.playback) else { return }
		guard channel.isPrivateMessage, channel.isPrivateMessageForZNCUser == false else { return }

		let command = "clear \(channel.name)"
		if isConnectedToZNC {
			sendCommand(command, toZNCModuleNamed: IRCServerQuirks.ZNC.playbackModule)
		} else {
			send("PRIVMSG", arguments: ["*playback", command])
		}
	}

	func requestPlayback() {
		guard isCapabilityEnabled(.playback) else { return }

		/* chathistory is requested per target as channels are joined and only
		 fetches what the local scrollback lacks. It wins over a bouncer replaying
		 everything. */
		guard isCapabilityEnabled(.chatHistory) == false else { return }

		let command = PlaybackRequestPolicy.command(
			successfulConnects: successfulConnects,
			onlyLatestOnFirstConnect: config.zncOnlyPlaybackLatest,
			lastMessageServerTime: lastMessageServerTime
		)

		if isConnectedToZNC {
			sendCommand(command, toZNCModuleNamed: IRCServerQuirks.ZNC.playbackModule)
		} else {
			send("PRIVMSG", arguments: ["*playback", command])
		}
	}
}
