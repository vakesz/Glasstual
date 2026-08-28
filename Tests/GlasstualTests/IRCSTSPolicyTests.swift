@testable import Glasstual
import XCTest

/** *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
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
@MainActor
class STSPolicyTests: XCTestCase {
	func store() -> STSPolicyStore {
		/* A nil user defaults store keeps everything in memory. */
		STSPolicyStore(userDefaults: nil)
	}

	func testParseFullCapabilityValues() throws {
		let values = try XCTUnwrap(STSCapabilityValues.values(fromCapabilityValues: [
			"port=6697",
			"duration=300",
			"preload",
		]))

		XCTAssertEqual(values.port, 6697)

		XCTAssertTrue(values.hasDuration)

		XCTAssertEqual(values.duration, 300)

		XCTAssertTrue(values.preload)
	}

	func testParseDurationOnly() throws {
		let values = try XCTUnwrap(STSCapabilityValues.values(fromCapabilityValues: ["duration=0"]))

		XCTAssertEqual(values.port, 0)

		XCTAssertTrue(values.hasDuration)

		XCTAssertEqual(values.duration, 0)

		XCTAssertFalse(values.preload)
	}

	func testParseRejectsInvalidPortAndUnknownKeys() throws {
		/* "port" is a key the parser knows, so the value survives even when the
		 port itself does not parse. */
		let values = try XCTUnwrap(STSCapabilityValues.values(fromCapabilityValues: [
			"port=notaport",
			"port=99999",
		]))

		XCTAssertEqual(values.port, 0)

		XCTAssertNil(STSCapabilityValues.values(fromCapabilityValues: []))
		XCTAssertNil(STSCapabilityValues.values(fromCapabilityValues: ["vendor=thing"]))
	}

	func testStoreAndRetrievePolicy() throws {
		let store = store()
		let policy = STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: false)

		store.setPolicy(policy, forHost: "irc.example.net")

		let stored = try XCTUnwrap(store.policy(forHost: "IRC.EXAMPLE.NET")) // Case insensitive

		XCTAssertEqual(stored.port, 6697)
	}

	func testExpiredPolicyIsForgotten() {
		let store = store()
		let policy = STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: -1), preload: false)

		store.setPolicy(policy, forHost: "irc.example.net")
		XCTAssertNil(store.policy(forHost: "irc.example.net"))
	}

	func testPolicyPersistsAndReloadsFromUserDefaults() throws {
		let suiteName = "\(className).\(UUID().uuidString)"
		let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
		defer { userDefaults.removePersistentDomain(forName: suiteName) }

		let store = STSPolicyStore(userDefaults: userDefaults)
		let policy = STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: true)

		store.setPolicy(policy, forHost: "IRC.EXAMPLE.NET")

		let storedDictionary = try XCTUnwrap(userDefaults.dictionary(forKey: IRCSTSPolicyStoreDefaultsKey))

		XCTAssertNotNil(storedDictionary["irc.example.net"])

		let reloadedStore = STSPolicyStore(userDefaults: userDefaults)
		let reloadedPolicy = try XCTUnwrap(reloadedStore.policy(forHost: "irc.example.net"))

		XCTAssertEqual(reloadedPolicy.port, 6697)
		XCTAssertTrue(reloadedPolicy.preload)
	}

	func testApplyPolicyForcesSecuredConnectionOnPolicyPort() throws {
		let store = store()

		store.setPolicy(
			STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: false),
			forHost: "irc.example.net"
		)

		let enforced = try XCTUnwrap(store.enforcedEndpoint(forHost: "irc.example.net"))

		XCTAssertEqual(enforced.port, 6697)
	}

	func testApplyPolicyNeverDowngrades() {
		let store = store()

		/* No policy: nothing to enforce, so the caller keeps what it had. */
		XCTAssertNil(store.enforcedEndpoint(forHost: "irc.example.net"))
	}

	func testPlaintextConnectionWithPortDecidesUpgrade() throws {
		let store = store()
		let values = try XCTUnwrap(STSCapabilityValues.values(fromCapabilityValues: [
			"port=6697",
			"duration=300",
		]))
		let action: IRCSTSPolicyAction = store.applyCapabilityValues(
			values,
			forHost: "irc.example.net",
			connectedPort: 6667,
			secured: false,
			certificateChainValidated: false
		)

		XCTAssertEqual(action, .upgrade(port: 6697))
		/* Nothing is stored from an insecure connection. */
		XCTAssertNil(store.policy(forHost: "irc.example.net"))
	}

	func testSecuredConnectionStoresPolicy() throws {
		let store = store()
		let values = try XCTUnwrap(STSCapabilityValues.values(fromCapabilityValues: ["duration=300"]))
		let action: IRCSTSPolicyAction = store.applyCapabilityValues(
			values,
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: true
		)

		XCTAssertEqual(action, .stored(port: 6697))

		let policy = try XCTUnwrap(store.policy(forHost: "irc.example.net"))

		XCTAssertEqual(policy.port, 6697) // The connected port when none advertised
	}

	func testSecuredConnectionWithZeroDurationClearsPolicy() throws {
		let store = store()

		store.setPolicy(
			STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: false),
			forHost: "irc.example.net"
		)

		let values = try XCTUnwrap(STSCapabilityValues.values(fromCapabilityValues: ["duration=0"]))
		let action: IRCSTSPolicyAction = store.applyCapabilityValues(
			values,
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: true
		)

		XCTAssertEqual(action, .cleared)
		XCTAssertNil(store.policy(forHost: "irc.example.net"))
	}
}
