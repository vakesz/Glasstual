// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The ZNC playback request for this connect.

 A reconnect asks for everything since the last line the client saw; a first
 connect asks for everything, unless the user only wants the latest. */
func zncPlaybackCommand(
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

extension Client {
	func clearPlayback(for channel: Channel) {
		guard isCapabilityEnabled(.playback) else { return }
		guard channel.isPrivateMessage, channel.isPrivateMessageForZNCUser == false else { return }

		let command = "clear \(channel.name)"
		if znc.isConnected {
			sendCommand(command, toZNCModuleNamed: ServerQuirks.ZNC.playbackModule)
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

		let command = zncPlaybackCommand(
			successfulConnects: successfulConnects,
			onlyLatestOnFirstConnect: config.zncOnlyPlaybackLatest,
			lastMessageServerTime: lastMessageServerTime
		)

		if znc.isConnected {
			sendCommand(command, toZNCModuleNamed: ServerQuirks.ZNC.playbackModule)
		} else {
			send("PRIVMSG", arguments: ["*playback", command])
		}
	}
}
