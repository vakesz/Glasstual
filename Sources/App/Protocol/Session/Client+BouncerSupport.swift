// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

private let bouncerSupportLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCBouncer"
)

extension Client {
	func clearZNCPlayback(for channel: Channel) {
		guard znc.isConnected else { return }
		clearPlayback(for: channel)
	}

	func nicknameIsZNCUser(_ nickname: String) -> Bool {
		znc.isConnected && nickname.hasPrefix(ServerQuirks.ZNC.modulePrefix)
	}

	/// Folded the way the server folds nicknames, so `*Status` and `*status`
	/// name the same module.
	func nickname(_ nickname: String, isZNCUser zncNickname: String) -> Bool {
		guard let moduleNickname = nicknameAsZNCUser(zncNickname) else { return false }
		return casefoldNickname(nickname) == casefoldNickname(moduleNickname)
	}

	func nicknameAsZNCUser(_ nickname: String) -> String? {
		guard znc.isConnected else { return nil }
		return ServerQuirks.ZNC.nickname(forModuleNamed: nickname)
	}

	/** Whether `message` may raise a notification.

	 Chat history the client asked for never does. Past that the question is
	 only what a bouncer replays: a playback batch is recognised by its type
	 where the server negotiated `batch`, and by the historic flag where it did
	 not. */
	func isSafeToPostNotification(for message: Message, in channel: Channel?) -> Bool {
		guard batchMessage(ofType: ServerQuirks.chatHistoryBatchType, containing: message) == nil else {
			return false
		}

		guard znc.isConnected else { return true }

		if config.zncIgnoreUserNotifications, channel.map({ nicknameIsZNCUser($0.name) }) == true {
			return false
		}

		guard config.zncIgnorePlaybackNotifications else { return true }

		if isCapabilityEnabled(.batch) {
			return message.parentBatchMessage?.batchType != ServerQuirks.ZNC.playbackBatchType
		}

		return message.isHistoric == false
	}

	func detectZNC(from message: Message) {
		guard znc.isConnected == false, message.senderIsServer else { return }
		guard message.senderNickname == ServerQuirks.ZNC.serverName else { return }

		znc.isConnected = true
		bouncerSupportLogger.info("ZNC detected")
	}

	func sendCommand(_ command: String, toZNCModuleNamed module: String) {
		guard let destination = nicknameAsZNCUser(module) else { return }
		sendLine("ZNC \(destination) \(command)")
	}
}
