// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual

/// An IRC session double that records network and presentation output without
/// opening a socket. Tests opt into real incoming-message handling when they
/// need to exercise the production state machine.
@MainActor
final class TestServerSession: ServerSession {
	let sentCapabilityCommands = NSMutableArray()
	let sentLines = NSMutableArray()
	private(set) var processedMessages: [Message] = []
	let printedLines = NSMutableArray()
	var forwardsProcessedMessages = false

	/** The window, menus and application this session talks to. Held here rather
	 than reached for through the application's singletons, so a test session
	 works with no running user interface. */
	private(set) var fixture: ChatEnvironmentFixture!

	@MainActor convenience init() {
		self.init(configDictionary: [:])
	}

	@MainActor convenience init(configDictionary dictionary: [String: Any]) {
		self.init(configDictionary: dictionary, nicknamePassword: nil)
	}

	/** The password is applied after construction so that
	 `ServerSession.init(config:)` finds nothing pending and writes nothing: reads
	 come back from the pending value and never reach the real keychain. */
	@MainActor convenience init(
		configDictionary dictionary: [String: Any],
		nicknamePassword: String?,
		fixture: ChatEnvironmentFixture = ChatEnvironmentFixture()
	) {
		self.init(
			config: PropertyListModel.decode(
				ServerConfig.self,
				from: [String: PropertyListValue](propertyList: dictionary) ?? [:]
			) ?? ServerConfig(),
			environment: fixture.environment
		)

		self.fixture = fixture
		config.pendingNicknamePassword = nicknamePassword.map(PendingKeychainSecret.set) ?? .unchanged
		linePrintObserver = { [weak self] request in
			self?.recordPrintedLine(request)
		}
	}

	/// The window double this session draws into.
	var recordedOutput: RecordingSessionOutput {
		fixture.output
	}

	static func testChannelUser(nickname: String, on session: ServerSession) -> Member {
		Member(user: User(nickname: nickname), prefixes: session.currentUserPrefixes)
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
		processedMessages.append(message)

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
		line["channel"] = request.conversation
		line["nickname"] = request.nickname

		printedLines.add(line)
	}
}

/** Parsing a line the way a session would.

 Production hands the parser a ``MessageParsingContext`` and links the batch in a
 second step, which is what the socket reader does. A test that only wants "the
 line as this session would read it" says so here rather than repeating both
 halves at every call site. */
extension Message {
	@MainActor
	init?(line: String, on session: ServerSession) {
		guard let parsed = Message(line: line, context: session.messageParsingContext) else { return nil }

		self = parsed
		session.resolveBatch(of: &self)
	}
}
