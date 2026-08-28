/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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
final class IRCClientEncodingFilteringTests: XCTestCase {
	func testUTF8OnlyOverridesConfiguredEncodings() {
		let policy = IRCTextEncodingPolicy(
			primary: String.Encoding.ascii.rawValue,
			fallback: String.Encoding.isoLatin1.rawValue,
			requiresUTF8: true
		)

		XCTAssertEqual(policy.primary, .utf8)
		XCTAssertEqual(policy.fallback, .utf8)
	}

	func testEncodingFallsBackWithoutLossBeforeASCII() {
		let policy = IRCTextEncodingPolicy(
			primary: String.Encoding.ascii.rawValue,
			fallback: String.Encoding.utf8.rawValue,
			requiresUTF8: false
		)

		XCTAssertEqual(policy.encode("árvíz"), Data("árvíz".utf8))
	}

	func testDecodingFallsBackToLatin1ForArbitraryBytes() {
		let policy = IRCTextEncodingPolicy(
			primary: String.Encoding.utf8.rawValue,
			fallback: String.Encoding.ascii.rawValue,
			requiresUTF8: false
		)

		XCTAssertEqual(policy.decode(Data([0xFF])), "ÿ")
	}

	func testAddressBookLookupDerivesTrackingHostmaskAndCacheKeys() {
		XCTAssertEqual(
			IRCAddressBookLookupPolicy.trackingHostmask(forNickname: "Alice"),
			"Alice!*@*"
		)
		XCTAssertEqual(
			IRCAddressBookLookupPolicy.cacheKeys(forHostmask: "Alice!user@example.com"),
			["Alice!user@example.com", "Alice!*@*"]
		)
	}

	func testOutputSuppressionHonorsDestinationRestrictions() {
		let rule = IRCOutputSuppressionRule(pattern: "^secret$", channel: true)

		XCTAssertTrue(
			IRCOutputSuppressionPolicy.matches(message: "secret", destination: .channel, rules: [rule])
		)
		XCTAssertFalse(
			IRCOutputSuppressionPolicy.matches(message: "secret", destination: .console, rules: [rule])
		)
		XCTAssertFalse(
			IRCOutputSuppressionPolicy.matches(message: "public", destination: .channel, rules: [rule])
		)
	}

	func testOutputSuppressionRejectsInvalidPatternsAndOtherDestinations() {
		let invalidRule = IRCOutputSuppressionRule(pattern: "(", console: true)
		let utilityRule = IRCOutputSuppressionRule(pattern: ".*", channel: true, privateMessage: true)

		XCTAssertFalse(
			IRCOutputSuppressionPolicy.matches(message: "anything", destination: .console, rules: [invalidRule])
		)
		XCTAssertFalse(
			IRCOutputSuppressionPolicy.matches(message: "anything", destination: .other, rules: [utilityRule])
		)
	}
}
