/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

@testable import Glasstual
import XCTest

@MainActor
final class IRCClientConnectionDelegatePolicyTests: XCTestCase {
	func testConnectionErrorWireContractPreservesLegacyValues() {
		XCTAssertEqual(connectionErrorDomain, "Glasstual.ConnectionError")
		XCTAssertEqual(ConnectionErrorCode.socket.rawValue, 999)
		XCTAssertEqual(ConnectionErrorCode.other.rawValue, 1000)
		XCTAssertEqual(ConnectionErrorCode.badCertificate.rawValue, 1001)
		XCTAssertEqual(ConnectionErrorCode.unableToSecure.rawValue, 1002)
	}

	func testTransitionRequiresConnectingOrConnectedState() {
		XCTAssertFalse(IRCClientDisconnectPolicy.shouldTransitionOff(isConnecting: false, isConnected: false))
		XCTAssertTrue(IRCClientDisconnectPolicy.shouldTransitionOff(isConnecting: true, isConnected: false))
		XCTAssertTrue(IRCClientDisconnectPolicy.shouldTransitionOff(isConnecting: false, isConnected: true))
	}

	func testBadCertificateErrorOverridesConfiguredDisconnectMode() {
		XCTAssertEqual(
			IRCClientDisconnectPolicy.effectiveMode(
				configured: .serverRedirect,
				errorDomain: connectionErrorDomain,
				errorCode: Int(ConnectionErrorCode.badCertificate.rawValue)
			),
			.badCertificate
		)
		XCTAssertEqual(
			IRCClientDisconnectPolicy.effectiveMode(
				configured: .serverRedirect,
				errorDomain: "different.domain",
				errorCode: Int(ConnectionErrorCode.badCertificate.rawValue)
			),
			.serverRedirect
		)
	}

	func testDisconnectDescriptionsPreserveLegacyCopy() {
		XCTAssertEqual(IRCConnectionStrings.disconnectReason(for: .normal), "Disconnected")
		XCTAssertEqual(IRCConnectionStrings.disconnectReason(for: .computerSleep), "Disconnected for Sleep Mode")
		XCTAssertEqual(
			IRCConnectionStrings.disconnectReason(for: .badCertificate),
			"Disconnected from server because of an untrusted certificate"
		)
		XCTAssertEqual(
			IRCConnectionStrings.disconnectReason(for: .serverRedirect),
			"Disconnected for server redirect"
		)
		XCTAssertEqual(
			IRCConnectionStrings.disconnectReason(for: .reachabilityChange),
			"Disconnected from server because the Internet is not reachable"
		)
	}

	func testRegistrationFallsBackToNicknameAndSelectsInvisibleMode() {
		XCTAssertEqual(
			IRCClientRegistrationPolicy.values(
				nickname: "Guest",
				username: "",
				realName: "",
				setInvisibleMode: true
			),
			.init(username: "Guest", realName: "Guest", modeSymbols: "8")
		)
	}

	func testHistoricMessagePolicyAdvancesOnlyNewHistoricServerTime() {
		XCTAssertTrue(
			IRCClientHistoricMessagePolicy.shouldAdvanceServerTime(
				isLoggedIn: true,
				isHistoric: true,
				receivedTime: 20,
				lastServerTime: 10
			)
		)
		XCTAssertFalse(
			IRCClientHistoricMessagePolicy.shouldAdvanceServerTime(
				isLoggedIn: true,
				isHistoric: true,
				receivedTime: 10,
				lastServerTime: 10
			)
		)
	}

	func testPlaybackMessagesOutsideChatHistoryBecomeCurrent() {
		XCTAssertTrue(
			IRCClientHistoricMessagePolicy.shouldMarkCurrent(
				playbackCapabilityEnabled: true,
				isContainedInChatHistoryBatch: false
			)
		)
		XCTAssertFalse(
			IRCClientHistoricMessagePolicy.shouldMarkCurrent(
				playbackCapabilityEnabled: true,
				isContainedInChatHistoryBatch: true
			)
		)
	}

	func testDelegateSelectorsRemainRuntimeVisible() {
		let selectors = [
			"resetAllPropertyValues",
			"changeStateOff",
			"changeStateOffWithError:",
			"ircConnection:willConnectToProxy:port:",
			"ircConnectionDidConnect:",
			"ircConnectionDidSecureConnection:withProtocolType:cipherSuite:",
			"ircConnectionDidCloseReadStream:",
			"ircConnection:didDisconnectWithError:",
			"ircConnection:didReceiveData:",
			"ircConnection:willSendData:",
			"processIncomingMessage:",
		]
		for selectorName in selectors {
			XCTAssertTrue(IRCClient.instancesRespond(to: NSSelectorFromString(selectorName)), selectorName)
		}
	}
}
