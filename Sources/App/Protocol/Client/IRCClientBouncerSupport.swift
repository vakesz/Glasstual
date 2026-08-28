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

struct BouncerNotificationContext {
	let isRequestedChatHistory: Bool
	let isConnectedToBouncer: Bool
	let ignoresBouncerUsers: Bool
	let channelIsBouncerUser: Bool
	let ignoresPlayback: Bool
	let supportsBatch: Bool
	let batchType: String?
	let isHistoric: Bool
}

enum BouncerNotificationPolicy {
	static func shouldPost(_ context: BouncerNotificationContext) -> Bool {
		guard context.isRequestedChatHistory == false else { return false }
		guard context.isConnectedToBouncer else { return true }
		guard context.ignoresBouncerUsers == false || context.channelIsBouncerUser == false else { return false }
		guard context.ignoresPlayback else { return true }

		if context.supportsBatch {
			return context.batchType != IRCServerQuirks.ZNC.playbackBatchType
		}

		return context.isHistoric == false
	}
}

public extension IRCClient {
	@objc(zncPlaybackClearChannel:)
	internal func clearZNCPlayback(for channel: IRCChannel) {
		guard isConnectedToZNC else { return }
		clearPlayback(for: channel)
	}

	@objc(nicknameIsZNCUser:)
	func nicknameIsZNCUser(_ nickname: String) -> Bool {
		isConnectedToZNC && nickname.hasPrefix(IRCServerQuirks.ZNC.modulePrefix)
	}

	@objc(nickname:isZNCUser:)
	func nickname(_ nickname: String, isZNCUser zncNickname: String) -> Bool {
		nickname == nicknameAsZNCUser(zncNickname)
	}

	@objc(nicknameAsZNCUser:)
	func nicknameAsZNCUser(_ nickname: String) -> String? {
		guard isConnectedToZNC else { return nil }
		return IRCServerQuirks.ZNC.nickname(forModuleNamed: nickname)
	}

	@objc(isSafeToPostNotificationForMessage:inChannel:)
	internal func isSafeToPostNotification(for message: Message, in channel: IRCChannel?) -> Bool {
		let requestedHistory = batchMessage(ofType: IRCServerQuirks.chatHistoryBatchType, containing: message) != nil
		let channelIsBouncerUser = channel.map { nicknameIsZNCUser($0.name) } ?? false

		let context = BouncerNotificationContext(
			isRequestedChatHistory: requestedHistory,
			isConnectedToBouncer: isConnectedToZNC,
			ignoresBouncerUsers: config.zncIgnoreUserNotifications,
			channelIsBouncerUser: channelIsBouncerUser,
			ignoresPlayback: config.zncIgnorePlaybackNotifications,
			supportsBatch: isCapabilityEnabled(.batch),
			batchType: message.parentBatchMessage?.batchType,
			isHistoric: message.isHistoric
		)
		return BouncerNotificationPolicy.shouldPost(context)
	}

	@objc(updateConnectedToZNCPropertyWithMessage:)
	internal func detectZNC(from message: Message) {
		guard isConnectedToZNC == false, message.senderIsServer else { return }
		guard message.senderNickname == IRCServerQuirks.ZNC.serverName else { return }

		isConnectedToZNC = true
		bouncerSupportLogger.info("ZNC detected")
	}

	@objc(sendCommand:toZNCModuleNamed:)
	func sendCommand(_ command: String, toZNCModuleNamed module: String) {
		guard let destination = nicknameAsZNCUser(module) else { return }
		sendLine("ZNC \(destination) \(command)")
	}
}
