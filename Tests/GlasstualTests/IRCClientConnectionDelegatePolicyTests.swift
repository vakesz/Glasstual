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

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Client disconnect and registration policy")
struct IRCClientConnectionDelegatePolicyTests {
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

	@Test("Only a connecting or connected client transitions off")
	func transitionRequiresConnectingOrConnectedState() {
		#expect(IRCClientDisconnectPolicy.shouldTransitionOff(isConnecting: false, isConnected: false) == false)
		#expect(IRCClientDisconnectPolicy.shouldTransitionOff(isConnecting: true, isConnected: false))
		#expect(IRCClientDisconnectPolicy.shouldTransitionOff(isConnecting: false, isConnected: true))
	}

	@Test("An untrusted certificate overrides the configured disconnect mode")
	func badCertificateErrorOverridesConfiguredDisconnectMode() {
		#expect(
			IRCClientDisconnectPolicy.effectiveMode(
				configured: .serverRedirect,
				errorDomain: connectionErrorDomain,
				errorCode: Int(ConnectionErrorCode.badCertificate.rawValue)
			) == .badCertificate
		)
		#expect(
			IRCClientDisconnectPolicy.effectiveMode(
				configured: .serverRedirect,
				errorDomain: "different.domain",
				errorCode: Int(ConnectionErrorCode.badCertificate.rawValue)
			) == .serverRedirect
		)
	}

	@Test("Each disconnect mode keeps the copy the user is shown")
	func disconnectDescriptionsPreserveLegacyCopy() {
		#expect(IRCConnectionStrings.disconnectReason(for: .normal) == "Disconnected")
		#expect(IRCConnectionStrings.disconnectReason(for: .computerSleep) == "Disconnected for Sleep Mode")
		#expect(
			IRCConnectionStrings.disconnectReason(for: .badCertificate)
				== "Disconnected from server because of an untrusted certificate"
		)
		#expect(
			IRCConnectionStrings.disconnectReason(for: .serverRedirect)
				== "Disconnected for server redirect"
		)
		#expect(
			IRCConnectionStrings.disconnectReason(for: .reachabilityChange)
				== "Disconnected from server because the Internet is not reachable"
		)
	}

	@Test("An empty username and real name fall back to the nickname, and invisible mode is selected")
	func registrationFallsBackToNicknameAndSelectsInvisibleMode() {
		#expect(
			IRCClientRegistrationPolicy.values(
				nickname: "Guest",
				username: "",
				realName: "",
				setInvisibleMode: true
			) == .init(username: "Guest", realName: "Guest", modeSymbols: "8")
		)
	}

	@Test("The stored server time only advances for a newer stamped message")
	func historicMessagePolicyAdvancesOnlyNewServerTime() {
		#expect(
			IRCClientHistoricMessagePolicy.shouldAdvanceServerTime(
				isLoggedIn: true,
				hasServerTime: true,
				receivedTime: 20,
				lastServerTime: 10
			)
		)
		#expect(
			IRCClientHistoricMessagePolicy.shouldAdvanceServerTime(
				isLoggedIn: true,
				hasServerTime: true,
				receivedTime: 10,
				lastServerTime: 10
			) == false
		)
		#expect(
			IRCClientHistoricMessagePolicy.shouldAdvanceServerTime(
				isLoggedIn: true,
				hasServerTime: false,
				receivedTime: 20,
				lastServerTime: 10
			) == false
		)
	}
}
