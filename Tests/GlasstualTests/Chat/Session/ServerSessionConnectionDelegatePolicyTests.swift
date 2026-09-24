// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Server session disconnect and registration policy")
struct ServerSessionConnectionDelegatePolicyTests {
	/// The socket layer reports failures as an `NSError` in this domain, and
	/// `SessionDisconnectMode.effective(configured:errorDomain:errorCode:)`
	/// branches on the code, so the pairing has to survive.
	@Test("A connection failure keeps its legacy domain and codes")
	func connectionErrorWireContractPreservesLegacyValues() {
		#expect(connectionErrorDomain == "Glasstual.ConnectionError")
		#expect(ConnectionErrorCode.socket.rawValue == 999)
		#expect(ConnectionErrorCode.other.rawValue == 1000)
		#expect(ConnectionErrorCode.badCertificate.rawValue == 1001)
		#expect(ConnectionErrorCode.unableToSecure.rawValue == 1002)
	}

	@Test("An untrusted certificate overrides the configured disconnect mode")
	func badCertificateErrorOverridesConfiguredDisconnectMode() {
		#expect(
			SessionDisconnectMode.effective(
				configured: .serverRedirect,
				errorDomain: connectionErrorDomain,
				errorCode: Int(ConnectionErrorCode.badCertificate.rawValue)
			) == .badCertificate
		)
		#expect(
			SessionDisconnectMode.effective(
				configured: .serverRedirect,
				errorDomain: "different.domain",
				errorCode: Int(ConnectionErrorCode.badCertificate.rawValue)
			) == .serverRedirect
		)
	}

	@Test("Each disconnect mode keeps the copy the user is shown")
	func disconnectDescriptionsPreserveLegacyCopy() {
		#expect(SessionDisconnectMode.normal.reasonText == "Disconnected")
		#expect(SessionDisconnectMode.computerSleep.reasonText == "Disconnected for Sleep Mode")
		#expect(
			SessionDisconnectMode.badCertificate.reasonText
				== "Disconnected from server because of an untrusted certificate"
		)
		#expect(
			SessionDisconnectMode.serverRedirect.reasonText
				== "Disconnected for server redirect"
		)
		#expect(
			SessionDisconnectMode.reachabilityChange.reasonText
				== "Disconnected from server because the Internet is not reachable"
		)
	}

	@Test("Disconnecting preserves server lines already queued for rendering")
	func disconnectPreservesQueuedServerLines() async {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = window.transcriptControllers.controller(for: session)
		var renderedLineCount = 0

		for index in 0 ..< 16 {
			var line = ChatLine()
			line.messageBody = "server line \(index)"
			line.lineType = .debug
			controller.print(line) { _ in
				renderedLineCount += 1
			}
		}

		session.setConnectionTransportForTesting(.connecting)
		session.changeStateOff()
		await controller.drainRenderJobs()

		#expect(renderedLineCount == 16)
	}

	@Test("An empty username and real name fall back to the nickname, and invisible mode is selected")
	func registrationFallsBackToNicknameAndSelectsInvisibleMode() {
		let session = TestServerSession(configDictionary: [
			"nickname": "Guest",
			"username": "",
			"realName": "",
			"setInvisibleModeOnConnect": true,
		])

		session.connectionDidConnect()

		#expect(session.sentLines.contains("USER Guest 8 * :Guest"))
	}

	@Test("A configured username and real name register as they were typed, without invisible mode")
	func registrationSendsConfiguredNamesAndPlainMode() {
		let session = TestServerSession(configDictionary: [
			"nickname": "Guest",
			"username": "guest",
			"realName": "A Guest",
			"setInvisibleModeOnConnect": false,
		])

		session.connectionDidConnect()

		#expect(session.sentLines.contains("USER guest 0 * :A Guest"))
	}

	@Test("The stored server time only advances for a newer stamped message")
	func replayedMessagePolicyAdvancesOnlyNewServerTime() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me"])

		session.isLoggedIn = true
		session.enableCapability(.serverTime)

		let stamped = try #require(Message(line: "@time=2026-01-01T00:00:20.000Z :s PING :x", on: session))

		session.processIncomingMessageOnMainActor(stamped)

		let advanced = session.lastMessageServerTime

		#expect(advanced == stamped.receivedAt.timeIntervalSince1970)

		let older = try #require(Message(line: "@time=2026-01-01T00:00:10.000Z :s PING :x", on: session))

		session.processIncomingMessageOnMainActor(older)

		#expect(session.lastMessageServerTime == advanced)

		let unstamped = try #require(Message(line: ":s PING :x", on: session))

		session.processIncomingMessageOnMainActor(unstamped)

		#expect(session.lastMessageServerTime == advanced)
	}
}
