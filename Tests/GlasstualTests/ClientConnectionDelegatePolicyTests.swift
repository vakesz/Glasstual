/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
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
			ClientDisconnectPolicy.effectiveMode(
				configured: .serverRedirect,
				errorDomain: connectionErrorDomain,
				errorCode: Int(ConnectionErrorCode.badCertificate.rawValue)
			) == .badCertificate
		)
		#expect(
			ClientDisconnectPolicy.effectiveMode(
				configured: .serverRedirect,
				errorDomain: "different.domain",
				errorCode: Int(ConnectionErrorCode.badCertificate.rawValue)
			) == .serverRedirect
		)
	}

	@Test("Each disconnect mode keeps the copy the user is shown")
	func disconnectDescriptionsPreserveLegacyCopy() {
		#expect(ConnectionStrings.disconnectReason(for: .normal) == "Disconnected")
		#expect(ConnectionStrings.disconnectReason(for: .computerSleep) == "Disconnected for Sleep Mode")
		#expect(
			ConnectionStrings.disconnectReason(for: .badCertificate)
				== "Disconnected from server because of an untrusted certificate"
		)
		#expect(
			ConnectionStrings.disconnectReason(for: .serverRedirect)
				== "Disconnected for server redirect"
		)
		#expect(
			ConnectionStrings.disconnectReason(for: .reachabilityChange)
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
		let controller = window.logControllers.controller(for: client)
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
		#expect(
			ClientRegistrationPolicy.values(
				nickname: "Guest",
				username: "",
				realName: "",
				setInvisibleMode: true
			) == .init(username: "Guest", realName: "Guest", modeSymbols: "8")
		)
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
