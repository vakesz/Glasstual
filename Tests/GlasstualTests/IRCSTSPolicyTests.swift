@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "STSPolicy.h"
/// #pragma mark -
/// #pragma mark Parsing
/// #pragma mark -
/// #pragma mark Storage and expiry
/// #pragma mark -
/// #pragma mark Applying a policy to connection parameters
/// #pragma mark -
/// #pragma mark Upgrade / store decisions
/** *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
@objc
class STSPolicyTests: XCTestCase {
	@objc
	func store() -> STSPolicyStore {
		/* A nil user defaults store keeps everything in memory. */
		STSPolicyStore(userDefaults: nil)
	}

	@objc
	func testParseFullCapabilityValues() {
		let values: STSCapabilityValues! = STSCapabilityValues.values(fromCapabilityValues: [
			"port=6697",
			"duration=300",
			"preload",
		])

		XCTAssertNotNil(values)

		XCTAssertEqual(values.port, 6697)

		XCTAssertTrue(values.hasDuration)

		XCTAssertEqual(values.duration, 300)

		XCTAssertTrue(values.preload)
	}

	@objc
	func testParseDurationOnly() {
		let values: STSCapabilityValues! = STSCapabilityValues.values(fromCapabilityValues: ["duration=0"])

		XCTAssertNotNil(values)

		XCTAssertEqual(values.port, 0)

		XCTAssertTrue(values.hasDuration)

		XCTAssertEqual(values.duration, 0)

		XCTAssertFalse(values.preload)
	}

	@objc
	func testParseRejectsInvalidPortAndUnknownKeys() {
		let values: STSCapabilityValues! = STSCapabilityValues.values(fromCapabilityValues: [
			"port=notaport",
			"port=99999",
		])

		XCTAssertNotNil(values) // "port" was recognised even though invalid

		XCTAssertEqual(values.port, 0)

		XCTAssertNil(STSCapabilityValues.values(fromCapabilityValues: []))
		XCTAssertNil(STSCapabilityValues.values(fromCapabilityValues: ["vendor=thing"]))
	}

	@objc
	func testStoreAndRetrievePolicy() {
		let store = store()
		let policy: STSPolicy! = STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: false)

		store.setPolicy(policy, forHost: "irc.example.net")

		let stored: STSPolicy! = store.policy(forHost: "IRC.EXAMPLE.NET") // Case insensitive

		XCTAssertNotNil(stored)
		XCTAssertEqual(stored.port, 6697)
	}

	@objc
	func testExpiredPolicyIsForgotten() {
		let store = store()
		let policy = STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: -1), preload: false)

		store.setPolicy(policy, forHost: "irc.example.net")
		XCTAssertNil(store.policy(forHost: "irc.example.net"))
	}

	@objc
	func testPolicyPersistsAndReloadsFromUserDefaults() {
		let suiteName: String! = String(format: "%@.%@", className, UUID().uuidString)
		let userDefaults: UserDefaults! = UserDefaults(suiteName: suiteName)

		userDefaults.removePersistentDomain(forName: suiteName)

		let store: STSPolicyStore! = STSPolicyStore(userDefaults: userDefaults)
		let policy: STSPolicy! = STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: true)

		store.setPolicy(policy, forHost: "IRC.EXAMPLE.NET")

		let storedDictionary = userDefaults.dictionary(forKey: IRCSTSPolicyStoreDefaultsKey)

		XCTAssertNotNil(storedDictionary?["irc.example.net"])

		let reloadedStore: STSPolicyStore! = STSPolicyStore(userDefaults: userDefaults)
		let reloadedPolicy: STSPolicy! = reloadedStore.policy(forHost: "irc.example.net")

		XCTAssertEqual(reloadedPolicy.port, 6697)
		XCTAssertTrue(reloadedPolicy.preload)
		userDefaults.removePersistentDomain(forName: suiteName)
	}

	@objc
	func testApplyPolicyForcesSecuredConnectionOnPolicyPort() {
		let store = store()

		store.setPolicy(
			STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: false),
			forHost: "irc.example.net"
		)

		var port: UInt16 = 6667
		var secured = ObjCBool(false)
		let applied = store.applyPolicy(forHost: "irc.example.net", toPort: &port, secured: &secured)

		XCTAssertTrue(applied)
		XCTAssertEqual(port, 6697)
		XCTAssertTrue(secured.boolValue)
	}

	@objc
	func testApplyPolicyNeverDowngrades() {
		let store = store()
		var port: UInt16 = 6697
		var secured = ObjCBool(true)
		/* No policy: parameters are left untouched, never downgraded. */
		let applied = store.applyPolicy(forHost: "irc.example.net", toPort: &port, secured: &secured)

		XCTAssertFalse(applied)
		XCTAssertEqual(port, 6697)
		XCTAssertTrue(secured.boolValue)
	}

	@objc
	func testPlaintextConnectionWithPortDecidesUpgrade() {
		let store = store()
		let values: STSCapabilityValues! = STSCapabilityValues.values(fromCapabilityValues: [
			"port=6697",
			"duration=300",
		])
		var upgradePort: UInt16 = 0
		let action: IRCSTSPolicyAction = store.applyCapabilityValues(
			values,
			forHost: "irc.example.net",
			connectedPort: 6667,
			secured: false,
			upgradePort: &upgradePort
		)

		XCTAssertEqual(action, .upgrade)
		XCTAssertEqual(upgradePort, 6697)
		/* Nothing is stored from an insecure connection. */
		XCTAssertNil(store.policy(forHost: "irc.example.net"))
	}

	@objc
	func testSecuredConnectionStoresPolicy() {
		let store = store()
		let values: STSCapabilityValues! = STSCapabilityValues.values(fromCapabilityValues: ["duration=300"])
		let action: IRCSTSPolicyAction = store.applyCapabilityValues(
			values,
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			upgradePort: nil
		)

		XCTAssertEqual(action, .stored)

		let policy: STSPolicy! = store.policy(forHost: "irc.example.net")

		XCTAssertNotNil(policy)
		XCTAssertEqual(policy.port, 6697) // The connected port when none advertised
	}

	@objc
	func testSecuredConnectionWithZeroDurationClearsPolicy() {
		let store = store()

		store.setPolicy(
			STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: false),
			forHost: "irc.example.net"
		)

		let values: STSCapabilityValues! = STSCapabilityValues.values(fromCapabilityValues: ["duration=0"])
		let action: IRCSTSPolicyAction = store.applyCapabilityValues(
			values,
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			upgradePort: nil
		)

		XCTAssertEqual(action, .cleared)
		XCTAssertNil(store.policy(forHost: "irc.example.net"))
	}
}
