import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "IRCCapability.h"
/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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
class IRCCapabilityRegistryTests: XCTestCase {
    @objc
    func registryWithGateAllowed(_ gateAllowed: Bool) -> UnsafeMutablePointer<IRCCapabilityRegistry> {
        let tags: UnsafeMutablePointer<IRCCapability>! = IRCCapability.capabilityNamed("message-tags", identifier: ClientIRCv3SupportedCapabilityMessageTags)
        let gated: UnsafeMutablePointer<IRCCapability>! = IRCCapability(name: "echo-message", identifier: ClientIRCv3SupportedCapabilityEchoMessage, requestedByDefault: true, preferenceGate: { () -> Bool in
            return gateAllowed
        }, dependencies: nil, negotiationHook: nil)
        let dependent: UnsafeMutablePointer<IRCCapability>! = IRCCapability(name: "draft/typing", identifier: 0, requestedByDefault: true, preferenceGate: nil, dependencies: ["message-tags"], negotiationHook: nil)
        let optional: UnsafeMutablePointer<IRCCapability>! = IRCCapability.capabilityNamed("draft/opt-in", identifier: 0, requestedByDefault: false)

        return IRCCapabilityRegistry(capabilities: [tags, gated, dependent, optional])
    }
    @objc
    func testParseCapabilityList() {
        let offered: NSDictionary! = IRCCapabilityRegistry.parseCapabilityList("multi-prefix SASL=PLAIN,EXTERNAL  cap-notify x=")

        XCTAssertEqualObjects(offered["multi-prefix"], [])
        XCTAssertEqualObjects(offered["sasl"], ["PLAIN", "EXTERNAL"])
        XCTAssertEqualObjects(offered["cap-notify"], [])
        XCTAssertEqualObjects(offered["x"], [])

        XCTAssertEqual(offered.count, 4)

        let empty = [:]

        XCTAssertEqualObjects(IRCCapabilityRegistry.parseCapabilityList(""), empty)
    }
    @objc
    func testParseCapabilityListUsesLastDuplicateAndIgnoresEmptyNamesAndValues() {
        let offered: NSDictionary! = IRCCapabilityRegistry.parseCapabilityList("SASL=PLAIN sasl=EXTERNAL,,SCRAM-SHA-256 =bad")

        XCTAssertEqualObjects(offered["sasl"], ["EXTERNAL", "SCRAM-SHA-256"])
        XCTAssertEqual(offered.count, 1)
    }
    @objc
    func testLookupIsCaseInsensitive() {
        let registry = self.registryWithGateAllowed(true)

        XCTAssertEqualObjects(registry.capabilityNamed("Message-Tags").name, "message-tags")

        XCTAssertNil(registry.capabilityNamed("unknown"))

        XCTAssertEqualObjects(registry.capabilityForIdentifier(ClientIRCv3SupportedCapabilityEchoMessage).name, "echo-message")

        XCTAssertNil(registry.capabilityForIdentifier(ClientIRCv3SupportedCapabilityBatch))
    }
    @objc
    func testRequestListRespectsPreferenceGate() {
        let offered: NSDictionary = ["message-tags": [], "echo-message": []]
        let allowed: [IRCCapability]! = self.registryWithGateAllowed(true).capabilitiesToRequestFromOffered(offered)

        XCTAssertEqualObjects(allowed.valueForKey("name"), ["message-tags", "echo-message"])

        let denied: [IRCCapability]! = self.registryWithGateAllowed(false).capabilitiesToRequestFromOffered(offered)

        XCTAssertEqualObjects(denied.valueForKey("name"), ["message-tags"])
        XCTAssertTrue(self.registryWithGateAllowed(true).isCapabilitySupported("echo-message"))
        XCTAssertFalse(self.registryWithGateAllowed(false).isCapabilitySupported("echo-message"))
    }
    @objc
    func testRequestListRespectsDependencies() {
        let registry = self.registryWithGateAllowed(true)
        let withoutTags: [IRCCapability]! = registry.capabilitiesToRequestFromOffered(["draft/typing": []])

        XCTAssertEqual(withoutTags.count, 0)

        let withTags: [IRCCapability]! = registry.capabilitiesToRequestFromOffered(["draft/typing": [], "message-tags": []])

        XCTAssertEqualObjects(withTags.valueForKey("name"), ["message-tags", "draft/typing"])
    }
    @objc
    func testCapabilitiesNotRequestedByDefaultAreSkipped() {
        let registry = self.registryWithGateAllowed(true)
        let request: [IRCCapability]! = registry.capabilitiesToRequestFromOffered(["draft/opt-in": []])

        XCTAssertEqual(request.count, 0)
    }
    @objc
    func testUnknownCapabilitiesAreNeverRequested() {
        let registry = self.registryWithGateAllowed(true)
        let request: [IRCCapability]! = registry.capabilitiesToRequestFromOffered(["example.com/vendor": []])

        XCTAssertEqual(request.count, 0)
    }
    @objc
    func testCyclicDependenciesAreNeverRequested() {
        let first: UnsafeMutablePointer<IRCCapability>! = IRCCapability(name: "first", identifier: 0, requestedByDefault: true, preferenceGate: nil, dependencies: ["second"], negotiationHook: nil)
        let second: UnsafeMutablePointer<IRCCapability>! = IRCCapability(name: "second", identifier: 0, requestedByDefault: true, preferenceGate: nil, dependencies: ["first"], negotiationHook: nil)
        let registry: UnsafeMutablePointer<IRCCapabilityRegistry>! = IRCCapabilityRegistry(capabilities: [first, second])
        let offered: NSDictionary = ["first": [], "second": []]

        XCTAssertEqual(registry.capabilitiesToRequestFromOffered(offered).count, 0)
    }
    @objc
    func testDefaultRegistryContents() {
        let registry: UnsafeMutablePointer<IRCCapabilityRegistry>! = IRCCapabilityRegistry.defaultRegistry()

        for name in ["away-notify", "batch", "cap-notify", "chghost", "echo-message", "message-tags", "multi-prefix", "sasl", "server-time", "standard-replies", "userhost-in-names", "znc.in/playback", "znc.in/self-message", "znc.in/server-time", "znc.in/server-time-iso", "znc.in/tlsinfo"] {
            XCTAssertNotNil(registry.capabilityNamed(name), "%@ is missing from the default registry", name)
        }

        XCTAssertNil(registry.capabilityNamed("identify-msg"))
        XCTAssertNil(registry.capabilityNamed("identify-ctcp"))
        XCTAssertNil(registry.capabilityNamed("plan.io/playback"))

        XCTAssertNotNil(registry.capabilityNamed("sasl").negotiationHook)

        /* Vendor variants switch on the generic bit too. */
        let zncServerTime: ClientIRCv3SupportedCapability = registry.capabilityNamed("znc.in/server-time-iso").identifier

        XCTAssertEqual(zncServerTime & ClientIRCv3SupportedCapabilityServerTime, ClientIRCv3SupportedCapabilityServerTime)

        let zncPlayback: ClientIRCv3SupportedCapability = registry.capabilityNamed("znc.in/playback").identifier

        XCTAssertEqual(zncPlayback & ClientIRCv3SupportedCapabilityPlayback, ClientIRCv3SupportedCapabilityPlayback)
    }
}