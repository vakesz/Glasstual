import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "IRCSTSPolicy.h"
// #pragma mark -
// #pragma mark Parsing
// #pragma mark -
// #pragma mark Storage and expiry
// #pragma mark -
// #pragma mark Applying a policy to connection parameters
// #pragma mark -
// #pragma mark Upgrade / store decisions
/* *********************************************************************
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
@objc
class IRCSTSPolicyTests: XCTestCase {
    @objc
    func store() -> UnsafeMutablePointer<IRCSTSPolicyStore> {
        /* A nil user defaults store keeps everything in memory. */
        return IRCSTSPolicyStore(userDefaults: nil)
    }
    @objc
    func testParseFullCapabilityValues() {
        let values: UnsafeMutablePointer<IRCSTSCapabilityValues>! = IRCSTSCapabilityValues.valuesFromCapabilityValues(["port=6697", "duration=300", "preload"])

        XCTAssertNotNil(values)

        XCTAssertEqual(values.port, 6697)

        XCTAssertTrue(values.hasDuration)

        XCTAssertEqual(values.duration, 300)

        XCTAssertTrue(values.preload)
    }
    @objc
    func testParseDurationOnly() {
        let values: UnsafeMutablePointer<IRCSTSCapabilityValues>! = IRCSTSCapabilityValues.valuesFromCapabilityValues(["duration=0"])

        XCTAssertNotNil(values)

        XCTAssertEqual(values.port, 0)

        XCTAssertTrue(values.hasDuration)

        XCTAssertEqual(values.duration, 0)

        XCTAssertFalse(values.preload)
    }
    @objc
    func testParseRejectsInvalidPortAndUnknownKeys() {
        let values: UnsafeMutablePointer<IRCSTSCapabilityValues>! = IRCSTSCapabilityValues.valuesFromCapabilityValues(["port=notaport", "port=99999"])

        XCTAssertNotNil(values) // "port" was recognised even though invalid

        XCTAssertEqual(values.port, 0)

        XCTAssertNil(IRCSTSCapabilityValues.valuesFromCapabilityValues([]))
        XCTAssertNil(IRCSTSCapabilityValues.valuesFromCapabilityValues(["vendor=thing"]))
    }
    @objc
    func testStoreAndRetrievePolicy() {
        let store = self.store()
        let policy: UnsafeMutablePointer<IRCSTSPolicy>! = IRCSTSPolicy(port: 6697, expiresAt: Date.dateWithTimeIntervalSinceNow(300), preload: false)

        store.setPolicy(policy, forHost: "irc.example.net")

        let stored: UnsafeMutablePointer<IRCSTSPolicy>! = store.policyForHost("IRC.EXAMPLE.NET") // Case insensitive

        XCTAssertNotNil(stored)
        XCTAssertEqual(stored.port, 6697)
    }
    @objc
    func testExpiredPolicyIsForgotten() {
        let store = self.store()
        let policy: UnsafeMutablePointer<IRCSTSPolicy>! = IRCSTSPolicy(port: 6697, expiresAt: Date.dateWithTimeIntervalSinceNow(1), preload: false)

        store.setPolicy(policy, forHost: "irc.example.net")
        XCTAssertNil(store.policyForHost("irc.example.net"))
    }
    @objc
    func testPolicyPersistsAndReloadsFromUserDefaults() {
        let suiteName: String! = String(format: "%@.%@", self.className, NSUUID.UUID.UUIDString)
        let userDefaults: NSUserDefaults! = NSUserDefaults(suiteName: suiteName)

        userDefaults.removePersistentDomainForName(suiteName)

        let store: UnsafeMutablePointer<IRCSTSPolicyStore>! = IRCSTSPolicyStore(userDefaults: userDefaults)
        let policy: UnsafeMutablePointer<IRCSTSPolicy>! = IRCSTSPolicy(port: 6697, expiresAt: Date.dateWithTimeIntervalSinceNow(300), preload: true)

        store.setPolicy(policy, forHost: "IRC.EXAMPLE.NET")

        let storedDictionary: NSDictionary! = userDefaults.dictionaryForKey(IRCSTSPolicyStoreDefaultsKey)

        XCTAssertNotNil(storedDictionary["irc.example.net"])

        let reloadedStore: UnsafeMutablePointer<IRCSTSPolicyStore>! = IRCSTSPolicyStore(userDefaults: userDefaults)
        let reloadedPolicy: UnsafeMutablePointer<IRCSTSPolicy>! = reloadedStore.policyForHost("irc.example.net")

        XCTAssertEqual(reloadedPolicy.port, 6697)
        XCTAssertTrue(reloadedPolicy.preload)
        userDefaults.removePersistentDomainForName(suiteName)
    }
    @objc
    func testApplyPolicyForcesSecuredConnectionOnPolicyPort() {
        let store = self.store()

        store.setPolicy(IRCSTSPolicy(port: 6697, expiresAt: Date.dateWithTimeIntervalSinceNow(300), preload: false), forHost: "irc.example.net")

        var port: uint16_t = 6667
        var secured = false
        let applied: Bool = store.applyPolicyForHost("irc.example.net", toPort: &port, secured: &secured)

        XCTAssertTrue(applied)
        XCTAssertEqual(port, 6697)
        XCTAssertTrue(secured)
    }
    @objc
    func testApplyPolicyNeverDowngrades() {
        let store = self.store()
        var port: uint16_t = 6697
        var secured = true
        /* No policy: parameters are left untouched, never downgraded. */
        let applied: Bool = store.applyPolicyForHost("irc.example.net", toPort: &port, secured: &secured)

        XCTAssertFalse(applied)
        XCTAssertEqual(port, 6697)
        XCTAssertTrue(secured)
    }
    @objc
    func testPlaintextConnectionWithPortDecidesUpgrade() {
        let store = self.store()
        let values: UnsafeMutablePointer<IRCSTSCapabilityValues>! = IRCSTSCapabilityValues.valuesFromCapabilityValues(["port=6697", "duration=300"])
        var upgradePort: uint16_t = 0
        let action: IRCSTSPolicyAction = store.applyCapabilityValues(values, forHost: "irc.example.net", connectedPort: 6667, secured: false, upgradePort: &upgradePort)

        XCTAssertEqual(action, IRCSTSPolicyActionUpgrade)
        XCTAssertEqual(upgradePort, 6697)
        /* Nothing is stored from an insecure connection. */
        XCTAssertNil(store.policyForHost("irc.example.net"))
    }
    @objc
    func testSecuredConnectionStoresPolicy() {
        let store = self.store()
        let values: UnsafeMutablePointer<IRCSTSCapabilityValues>! = IRCSTSCapabilityValues.valuesFromCapabilityValues(["duration=300"])
        let action: IRCSTSPolicyAction = store.applyCapabilityValues(values, forHost: "irc.example.net", connectedPort: 6697, secured: true, upgradePort: nil)

        XCTAssertEqual(action, IRCSTSPolicyActionStored)

        let policy: UnsafeMutablePointer<IRCSTSPolicy>! = store.policyForHost("irc.example.net")

        XCTAssertNotNil(policy)
        XCTAssertEqual(policy.port, 6697) // The connected port when none advertised
    }
    @objc
    func testSecuredConnectionWithZeroDurationClearsPolicy() {
        let store = self.store()

        store.setPolicy(IRCSTSPolicy(port: 6697, expiresAt: Date.dateWithTimeIntervalSinceNow(300), preload: false), forHost: "irc.example.net")

        let values: UnsafeMutablePointer<IRCSTSCapabilityValues>! = IRCSTSCapabilityValues.valuesFromCapabilityValues(["duration=0"])
        let action: IRCSTSPolicyAction = store.applyCapabilityValues(values, forHost: "irc.example.net", connectedPort: 6697, secured: true, upgradePort: nil)

        XCTAssertEqual(action, IRCSTSPolicyActionCleared)
        XCTAssertNil(store.policyForHost("irc.example.net"))
    }
}