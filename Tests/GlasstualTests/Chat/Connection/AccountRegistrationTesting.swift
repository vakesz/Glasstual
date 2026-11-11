// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Collects what a registration flow reports.
@MainActor
final class AccountRegistrationEventLog {
	private(set) var events: [AccountRegistrationEvent] = []

	var observer: @MainActor (AccountRegistrationEvent) -> Void {
		{ [weak self] event in self?.events.append(event) }
	}

	var last: AccountRegistrationEvent? {
		events.last
	}
}

struct KeychainWriteRefused: Error {}

/// A connected session with a keychain that never touches the real one.
@MainActor
func makeRegistrationSession(
	nickname: String = "ada",
	keychainWorks: Bool = true
) -> TestServerSession {
	let session = TestServerSession(configDictionary: ["nickname": nickname, "usesSASL": false], nicknamePassword: nil)
	session.config.nickname = nickname
	session.config.usesSASL = false
	session.config.username = ""
	session.setConnectionTransportForTesting(.connected)
	session.userNickname = nickname
	session.environment.services.credentialPersistence = KeychainPersistence(write: { _ in
		guard keychainWorks else { throw KeychainWriteRefused() }
	})

	return session
}

@MainActor
extension TestServerSession {
	func receive(_ line: String) throws {
		try dispatchIncomingMessage(#require(Message(line: line, on: self)))
	}

	var capabilityLines: [String] {
		sentCapabilityCommands.compactMap { $0 as? String }
	}

	var wireLines: [String] {
		sentLines.compactMap { $0 as? String }
	}

	var printedBodies: [String] {
		printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	/// Offers `capabilities` and acknowledges each one this session asks for.
	func negotiate(_ capabilities: String) throws {
		try receive(":irc.example.net CAP * LS :\(capabilities)")
		let requested = capabilityLines.filter { $0.hasPrefix("REQ ") }.map { String($0.dropFirst(4)) }
		for request in requested {
			try receive(":irc.example.net CAP ada ACK :\(request)")
		}
	}
}
