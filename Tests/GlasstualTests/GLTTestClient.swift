/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

@testable import Glasstual

final class GLTTestClientConfig: IRCClientConfig, @unchecked Sendable {
	var testNicknamePassword: String?

	override var nicknamePassword: String? {
		testNicknamePassword
	}

	override func writeNicknamePasswordToKeychain() {}
	override func writeProxyPasswordToKeychain() {}
}

/// An IRC client double that records network and presentation output without
/// opening a socket. Tests opt into real incoming-message handling when they
/// need to exercise the production state machine.
final class GLTTestClient: IRCClient, @unchecked Sendable {
	let sentCapabilityCommands = NSMutableArray()
	let sentLines = NSMutableArray()
	let processedMessages = NSMutableArray()
	let printedLines = NSMutableArray()
	var forwardsProcessedMessages = false

	convenience init() {
		self.init(configDictionary: [:])
	}

	convenience init(configDictionary dictionary: [String: Any]) {
		self.init(configDictionary: dictionary, nicknamePassword: nil)
	}

	convenience init(
		configDictionary dictionary: [String: Any],
		nicknamePassword: String?
	) {
		let config = GLTTestClientConfig(
			dictionary: dictionary,
			ignorePrivateMessages: false
		)
		config.testNicknamePassword = nicknamePassword

		self.init(config: config)
	}

	static func testChannelUser(nickname: String, on client: IRCClient) -> IRCChannelUser {
		IRCChannelUser(user: IRCUser(nickname: nickname, on: client))
	}

	func markAsLoggedIn() {
		setValue(true, forKey: "isLoggedIn")
	}

	override func sendCapability(_ subcommand: String, data: String?) {
		if let data {
			sentCapabilityCommands.add("\(subcommand) \(data)")
		} else {
			sentCapabilityCommands.add(subcommand)
		}
	}

	override func sendLine(_ string: String) {
		sentLines.add(string)
	}

	override func processIncomingMessage(_ message: Message) {
		processedMessages.add(message)

		if forwardsProcessedMessages {
			super.processIncomingMessage(message)
		}
	}

	override func print(
		_ messageBody: String,
		by nickname: String?,
		in channel: IRCChannel?,
		as lineType: TVCLogLineType,
		command: String?,
		receivedAt _: Date,
		isEncrypted _: Bool,
		escapeMessage _: Bool,
		referenceMessage _: Message?,
		completionBlock _: TVCLogControllerPrintOperationCompletionBlock?
	) {
		var line: [String: Any] = [
			"messageBody": messageBody,
			"lineType": NSNumber(value: lineType.rawValue),
		]

		line["command"] = command
		line["channel"] = channel
		line["nickname"] = nickname

		printedLines.add(line)
	}
}
