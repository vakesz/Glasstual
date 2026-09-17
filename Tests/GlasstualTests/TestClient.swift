// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual

/// An IRC client double that records network and presentation output without
/// opening a socket. Tests opt into real incoming-message handling when they
/// need to exercise the production state machine.
@MainActor
final class TestClient: Client {
	let sentCapabilityCommands = NSMutableArray()
	let sentLines = NSMutableArray()
	let processedMessages = NSMutableArray()
	let printedLines = NSMutableArray()
	var forwardsProcessedMessages = false

	/** The window, menus and application this client talks to. Held here rather
	 than reached for through the application's singletons, so a test client
	 works with no running user interface. */
	private(set) var fixture: ClientEnvironmentFixture!

	@MainActor convenience init() {
		self.init(configDictionary: [:])
	}

	@MainActor convenience init(configDictionary dictionary: [String: Any]) {
		self.init(configDictionary: dictionary, nicknamePassword: nil)
	}

	/** The password is applied after construction so that
	 `Client.init(config:)` finds nothing pending and writes nothing: reads
	 come back from the pending value and never reach the real keychain. */
	@MainActor convenience init(
		configDictionary dictionary: [String: Any],
		nicknamePassword: String?,
		fixture: ClientEnvironmentFixture = ClientEnvironmentFixture()
	) {
		self.init(
			config: PropertyListModel.decode(
				ClientConfig.self,
				from: [String: PropertyListValue](propertyList: dictionary) ?? [:]
			) ?? ClientConfig(),
			environment: fixture.environment
		)

		self.fixture = fixture
		config.pendingNicknamePassword = nicknamePassword.map(PendingKeychainSecret.set) ?? .unchanged
		linePrintObserver = { [weak self] request in
			self?.recordPrintedLine(request)
		}
	}

	/// The window double this client draws into.
	var recordedOutput: RecordingClientOutput {
		fixture.output
	}

	static func testChannelUser(nickname: String, on client: Client) -> ChannelUser {
		ChannelUser(user: User(nickname: nickname), prefixes: client.currentUserPrefixes)
	}

	func markAsLoggedIn() {
		isLoggedIn = true
	}

	override func sendCapability(_ subcommand: String, data: String?) {
		if forwardsSentLines {
			super.sendCapability(subcommand, data: data)
		}
		if let data {
			sentCapabilityCommands.add("\(subcommand) \(data)")
		} else {
			sentCapabilityCommands.add(subcommand)
		}
	}

	var forwardsSentLines = false

	override func sendLine(_ string: String) {
		sentLines.add(string)
		if forwardsSentLines {
			super.sendLine(string)
		}
	}

	override func processIncomingMessage(_ message: Message) {
		processedMessages.add(message)

		if forwardsProcessedMessages {
			super.processIncomingMessage(message)
		}
	}

	private func recordPrintedLine(_ request: LinePrintRequest) {
		var line: [String: Any] = [
			"messageBody": request.messageBody,
			"lineType": NSNumber(value: request.lineType.rawValue),
		]

		line["command"] = request.command
		line["channel"] = request.channel
		line["nickname"] = request.nickname

		printedLines.add(line)
	}
}
