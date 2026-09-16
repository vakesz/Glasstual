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
import os

private let bouncerSupportLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCBouncer"
)

extension Client {
	func clearZNCPlayback(for channel: Channel) {
		guard isConnectedToZNC else { return }
		clearPlayback(for: channel)
	}

	func nicknameIsZNCUser(_ nickname: String) -> Bool {
		isConnectedToZNC && nickname.hasPrefix(ServerQuirks.ZNC.modulePrefix)
	}

	/// Folded the way the server folds nicknames, so `*Status` and `*status`
	/// name the same module.
	func nickname(_ nickname: String, isZNCUser zncNickname: String) -> Bool {
		guard let moduleNickname = nicknameAsZNCUser(zncNickname) else { return false }
		return casefoldNickname(nickname) == casefoldNickname(moduleNickname)
	}

	func nicknameAsZNCUser(_ nickname: String) -> String? {
		guard isConnectedToZNC else { return nil }
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

		guard isConnectedToZNC else { return true }

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
		guard isConnectedToZNC == false, message.senderIsServer else { return }
		guard message.senderNickname == ServerQuirks.ZNC.serverName else { return }

		isConnectedToZNC = true
		bouncerSupportLogger.info("ZNC detected")
	}

	func sendCommand(_ command: String, toZNCModuleNamed module: String) {
		guard let destination = nicknameAsZNCUser(module) else { return }
		sendLine("ZNC \(destination) \(command)")
	}
}
