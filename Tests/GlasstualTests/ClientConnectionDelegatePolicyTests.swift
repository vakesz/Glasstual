// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Client disconnect and registration policy")
struct ClientConnectionDelegatePolicyTests {
	/// The socket layer reports failures as an `NSError` in this domain, and
	/// `effectiveMode(configured:errorDomain:errorCode:)` branches on the code,
	/// so the pairing has to survive.
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
			effectiveDisconnectMode(
				configured: .serverRedirect,
				errorDomain: connectionErrorDomain,
				errorCode: Int(ConnectionErrorCode.badCertificate.rawValue)
			) == .badCertificate
		)
		#expect(
			effectiveDisconnectMode(
				configured: .serverRedirect,
				errorDomain: "different.domain",
				errorCode: Int(ConnectionErrorCode.badCertificate.rawValue)
			) == .serverRedirect
		)
	}

	@Test("Each disconnect mode keeps the copy the user is shown")
	func disconnectDescriptionsPreserveLegacyCopy() {
		#expect(ClientDisconnectMode.normal.reasonText == "Disconnected")
		#expect(ClientDisconnectMode.computerSleep.reasonText == "Disconnected for Sleep Mode")
		#expect(
			ClientDisconnectMode.badCertificate.reasonText
				== "Disconnected from server because of an untrusted certificate"
		)
		#expect(
			ClientDisconnectMode.serverRedirect.reasonText
				== "Disconnected for server redirect"
		)
		#expect(
			ClientDisconnectMode.reachabilityChange.reasonText
				== "Disconnected from server because the Internet is not reachable"
		)
	}

	@Test("Disconnecting preserves server lines already queued for rendering")
	func disconnectPreservesQueuedServerLines() async {
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = window.transcriptControllers.controller(for: client)
		var renderedLineCount = 0

		for index in 0 ..< 16 {
			var line = LogLine()
			line.messageBody = "server line \(index)"
			line.lineType = .debug
			controller.print(line) { _ in
				renderedLineCount += 1
			}
		}

		client.isConnecting = true
		client.changeStateOff()
		await controller.drainRenderJobs()

		#expect(renderedLineCount == 16)
	}

	@Test("An empty username and real name fall back to the nickname, and invisible mode is selected")
	func registrationFallsBackToNicknameAndSelectsInvisibleMode() {
		let values = RegistrationValues(
			nickname: "Guest",
			username: "",
			realName: "",
			setInvisibleMode: true
		)

		#expect(values.username == "Guest")
		#expect(values.realName == "Guest")
		#expect(values.modeSymbols == "8")
	}

	@Test("The stored server time only advances for a newer stamped message")
	func historicMessagePolicyAdvancesOnlyNewServerTime() throws {
		let client = TestClient(configDictionary: ["nickname": "me"])

		client.isLoggedIn = true
		client.enableCapability(.serverTime)

		let stamped = try #require(Message(line: "@time=2026-01-01T00:00:20.000Z :s PING :x", on: client))

		client.processIncomingMessageOnMainActor(stamped)

		let advanced = client.lastMessageServerTime

		#expect(advanced == stamped.receivedAt.timeIntervalSince1970)

		let older = try #require(Message(line: "@time=2026-01-01T00:00:10.000Z :s PING :x", on: client))

		client.processIncomingMessageOnMainActor(older)

		#expect(client.lastMessageServerTime == advanced)

		let unstamped = try #require(Message(line: ":s PING :x", on: client))

		client.processIncomingMessageOnMainActor(unstamped)

		#expect(client.lastMessageServerTime == advanced)
	}
}
