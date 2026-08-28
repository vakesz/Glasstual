/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Client encoding and filtering policies")
struct IRCClientEncodingFilteringTests {
	@Test("A UTF-8 only network overrides both configured encodings")
	func utf8OnlyOverridesConfiguredEncodings() {
		let policy = IRCTextEncodingPolicy(
			primary: .ascii,
			fallback: .isoLatin1,
			requiresUTF8: true
		)

		#expect(policy.primary == .utf8)
		#expect(policy.fallback == .utf8)
	}

	@Test("Encoding falls back to the lossless encoding rather than mangling the text")
	func encodingFallsBackWithoutLossBeforeASCII() {
		let policy = IRCTextEncodingPolicy(
			primary: .ascii,
			fallback: .utf8,
			requiresUTF8: false
		)

		#expect(policy.encode("árvíz") == Data("árvíz".utf8))
	}

	@Test("Arbitrary bytes decode through Latin-1 rather than failing")
	func decodingFallsBackToLatin1ForArbitraryBytes() {
		let policy = IRCTextEncodingPolicy(
			primary: .utf8,
			fallback: .ascii,
			requiresUTF8: false
		)

		#expect(policy.decode(Data([0xFF])) == "ÿ")
	}

	@Test("A lookup derives the tracking hostmask and both cache keys")
	func addressBookLookupDerivesTrackingHostmaskAndCacheKeys() {
		#expect(IRCAddressBookLookupPolicy.trackingHostmask(forNickname: "Alice") == "Alice!*@*")
		#expect(
			IRCAddressBookLookupPolicy.cacheKeys(forHostmask: "Alice!user@example.com") ==
				["Alice!user@example.com", "Alice!*@*"]
		)
	}

	@Test("A suppression rule only fires for the destinations it names")
	func outputSuppressionHonorsDestinationRestrictions() {
		let rule = IRCOutputSuppressionRule(pattern: "^secret$", channel: true)

		#expect(IRCOutputSuppressionPolicy.matches(message: "secret", destination: .channel, rules: [rule]))
		#expect(
			IRCOutputSuppressionPolicy.matches(message: "secret", destination: .console, rules: [rule]) == false
		)
		#expect(
			IRCOutputSuppressionPolicy.matches(message: "public", destination: .channel, rules: [rule]) == false
		)
	}

	@Test("An unparsable pattern suppresses nothing, and neither does an unnamed destination")
	func outputSuppressionRejectsInvalidPatternsAndOtherDestinations() {
		let invalidRule = IRCOutputSuppressionRule(pattern: "(", console: true)
		let utilityRule = IRCOutputSuppressionRule(pattern: ".*", channel: true, privateMessage: true)

		#expect(
			IRCOutputSuppressionPolicy.matches(
				message: "anything",
				destination: .console,
				rules: [invalidRule]
			) == false
		)
		#expect(
			IRCOutputSuppressionPolicy.matches(
				message: "anything",
				destination: .other,
				rules: [utilityRule]
			) == false
		)
	}
}
