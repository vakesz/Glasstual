@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "Capability.h"
/** *********************************************************************
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
@MainActor
class CapabilityRegistryTests: XCTestCase {
	func testNativeCapabilityTypesPreserveObjectiveCRuntimeNames() {
		XCTAssertNotNil(NSClassFromString("IRCCapability"))
		XCTAssertNotNil(NSClassFromString("IRCCapabilityRegistry"))
		XCTAssertTrue(CapabilityRegistry.responds(to: NSSelectorFromString("parseCapabilityList:")))
	}

	@objc
	func registryWithGateAllowed(_ gateAllowed: Bool) -> CapabilityRegistry {
		let tags: Capability! = Capability.capability(
			named: "message-tags",
			identifier: ClientIRCv3SupportedCapability.messageTags
		)
		let gated: Capability! = Capability(
			name: "echo-message",
			identifier: ClientIRCv3SupportedCapability.echoMessage,
			requestedByDefault: true,
			preferenceGate: { () -> Bool in
				return gateAllowed
			},
			dependencies: nil,
			negotiationHook: nil
		)
		let dependent = Capability(
			name: "draft/typing",
			identifier: [],
			requestedByDefault: true,
			preferenceGate: nil,
			dependencies: ["message-tags"],
			negotiationHook: nil
		)
		let optional = Capability.capability(named: "draft/opt-in", identifier: [], requestedByDefault: false)

		return CapabilityRegistry(capabilities: [tags, gated, dependent, optional])
	}

	@objc
	func testParseCapabilityList() {
		let offered = CapabilityRegistry.parseCapabilityList("multi-prefix SASL=PLAIN,EXTERNAL  cap-notify x=")

		XCTAssertEqual(offered["multi-prefix"], [])
		XCTAssertEqual(offered["sasl"], ["PLAIN", "EXTERNAL"])
		XCTAssertEqual(offered["cap-notify"], [])
		XCTAssertEqual(offered["x"], [])

		XCTAssertEqual(offered.count, 4)

		let empty: [String: [String]] = [:]

		XCTAssertEqual(CapabilityRegistry.parseCapabilityList(""), empty)
	}

	@objc
	func testParseCapabilityListUsesLastDuplicateAndIgnoresEmptyNamesAndValues() {
		let offered = CapabilityRegistry.parseCapabilityList("SASL=PLAIN sasl=EXTERNAL,,SCRAM-SHA-256 =bad")

		XCTAssertEqual(offered["sasl"], ["EXTERNAL", "SCRAM-SHA-256"])
		XCTAssertEqual(offered.count, 1)
	}

	@objc
	func testLookupIsCaseInsensitive() {
		let registry = registryWithGateAllowed(true)

		XCTAssertEqual(registry.capability(named: "Message-Tags")?.name, "message-tags")

		XCTAssertNil(registry.capability(named: "unknown"))

		XCTAssertEqual(registry.capability(for: .echoMessage)?.name, "echo-message")

		XCTAssertNil(registry.capability(for: ClientIRCv3SupportedCapability.batch))
	}

	@objc
	func testRequestListRespectsPreferenceGate() {
		let offered: [String: [String]] = ["message-tags": [], "echo-message": []]
		let allowed = registryWithGateAllowed(true).capabilitiesToRequest(fromOffered: offered)

		XCTAssertEqual(allowed.map(\.name), ["message-tags", "echo-message"])

		let denied = registryWithGateAllowed(false).capabilitiesToRequest(fromOffered: offered)

		XCTAssertEqual(denied.map(\.name), ["message-tags"])
		XCTAssertTrue(registryWithGateAllowed(true).isCapabilitySupported("echo-message"))
		XCTAssertFalse(registryWithGateAllowed(false).isCapabilitySupported("echo-message"))
	}

	@objc
	func testRequestListRespectsDependencies() {
		let registry = registryWithGateAllowed(true)
		let withoutTags: [Capability]! = registry.capabilitiesToRequest(fromOffered: ["draft/typing": []])

		XCTAssertEqual(withoutTags.count, 0)

		let withTags: [Capability]! = registry.capabilitiesToRequest(fromOffered: [
			"draft/typing": [],
			"message-tags": [],
		])

		XCTAssertEqual(withTags.map(\.name), ["message-tags", "draft/typing"])
	}

	@objc
	func testCapabilitiesNotRequestedByDefaultAreSkipped() {
		let registry = registryWithGateAllowed(true)
		let request: [Capability]! = registry.capabilitiesToRequest(fromOffered: ["draft/opt-in": []])

		XCTAssertEqual(request.count, 0)
	}

	@objc
	func testUnknownCapabilitiesAreNeverRequested() {
		let registry = registryWithGateAllowed(true)
		let request: [Capability]! = registry.capabilitiesToRequest(fromOffered: ["example.com/vendor": []])

		XCTAssertEqual(request.count, 0)
	}

	@objc
	func testCyclicDependenciesAreNeverRequested() {
		let first = Capability(
			name: "first",
			identifier: [],
			requestedByDefault: true,
			preferenceGate: nil,
			dependencies: ["second"],
			negotiationHook: nil
		)
		let second = Capability(
			name: "second",
			identifier: [],
			requestedByDefault: true,
			preferenceGate: nil,
			dependencies: ["first"],
			negotiationHook: nil
		)
		let registry: CapabilityRegistry! = CapabilityRegistry(capabilities: [first, second])
		let offered: [String: [String]] = ["first": [], "second": []]

		XCTAssertEqual(registry.capabilitiesToRequest(fromOffered: offered).count, 0)
	}

	@objc
	func testDefaultRegistryContents() throws {
		let registry: CapabilityRegistry! = CapabilityRegistry.defaultRegistry

		for name in [
			"away-notify",
			"batch",
			"cap-notify",
			"chghost",
			"echo-message",
			"message-tags",
			"multi-prefix",
			"sasl",
			"server-time",
			"standard-replies",
			"userhost-in-names",
			"znc.in/playback",
			"znc.in/self-message",
			"znc.in/server-time",
			"znc.in/server-time-iso",
			"znc.in/tlsinfo",
		] {
			XCTAssertNotNil(registry.capability(named: name), "\(name) is missing from the default registry")
		}

		XCTAssertNil(registry.capability(named: "identify-msg"))
		XCTAssertNil(registry.capability(named: "identify-ctcp"))
		XCTAssertNil(registry.capability(named: "plan.io/playback"))

		XCTAssertNotNil(registry.capability(named: "sasl")?.negotiationHook)

		/* Vendor variants switch on the generic bit too. */
		let zncServerTime = try XCTUnwrap(registry.capability(named: "znc.in/server-time-iso")?.identifier)

		XCTAssertTrue(zncServerTime.contains(.serverTime))

		let zncPlayback = try XCTUnwrap(registry.capability(named: "znc.in/playback")?.identifier)

		XCTAssertTrue(zncPlayback.contains(.playback))
	}
}
