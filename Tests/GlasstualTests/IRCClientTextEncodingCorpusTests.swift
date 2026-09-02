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

/// Behaviour corpus for the encode/decode ladder applied to wire text.
///
/// The policy tries the configured primary encoding, then the configured
/// fallback, then a last resort that never fails: lossy ASCII when encoding
/// and ISO Latin-1 when decoding.
@MainActor
struct IRCClientTextEncodingCorpusTests {
	private static func policy(
		primary: String.Encoding,
		fallback: String.Encoding,
		requiresUTF8: Bool = false
	) -> IRCTextEncodingPolicy {
		IRCTextEncodingPolicy(
			primary: primary,
			fallback: fallback,
			requiresUTF8: requiresUTF8
		)
	}

	// MARK: - Encoding

	nonisolated struct EncodeCase: Sendable { // nonisolated: value
		let primary: String.Encoding
		let fallback: String.Encoding
		let text: String
		let bytes: [UInt8]

		init(primary: String.Encoding, fallback: String.Encoding, _ text: String, _ bytes: [UInt8]) {
			self.primary = primary
			self.fallback = fallback
			self.text = text
			self.bytes = bytes
		}
	}

	nonisolated static let encodeCases: [EncodeCase] = [ // nonisolated: let
		/* The primary encoding is used whenever it can represent the text. */
		EncodeCase(primary: .utf8, fallback: .isoLatin1, "hello", [104, 101, 108, 108, 111]),
		EncodeCase(primary: .utf8, fallback: .isoLatin1, "h\u{00E9}llo", [104, 195, 169, 108, 108, 111]),
		EncodeCase(primary: .ascii, fallback: .isoLatin1, "hello", [104, 101, 108, 108, 111]),
		/* ASCII cannot hold U+00E9, so the Latin-1 fallback takes over. */
		EncodeCase(primary: .ascii, fallback: .isoLatin1, "h\u{00E9}llo", [104, 233, 108, 108, 111]),
		EncodeCase(primary: .isoLatin1, fallback: .utf8, "\u{00E9}", [233]),
		/* Neither Latin-1 nor ASCII holds U+2713, so UTF-8 fallback wins. */
		EncodeCase(primary: .isoLatin1, fallback: .utf8, "\u{2713}", [226, 156, 147]),
		EncodeCase(primary: .utf8, fallback: .ascii, "\u{2713}", [226, 156, 147]),
		/* An empty string encodes to no bytes under every encoding. */
		EncodeCase(primary: .ascii, fallback: .isoLatin1, "", []),
	]

	@Test(arguments: Self.encodeCases)
	func encodesWithoutLossWhereverPossible(testCase: EncodeCase) throws {
		let policy = Self.policy(primary: testCase.primary, fallback: testCase.fallback)
		let encoded = try #require(policy.encode(testCase.text))

		#expect(Array(encoded) == testCase.bytes)
	}

	/// When no configured encoding can represent the text, the last resort is
	/// a lossy ASCII conversion rather than a failure.
	@Test(arguments: ["\u{2713}", "\u{65E5}\u{672C}", "\u{1F600}"])
	func fallsBackToLossyAsciiAsALastResort(text: String) throws {
		let policy = Self.policy(primary: .ascii, fallback: .isoLatin1)
		let encoded = try #require(policy.encode(text))

		/* The conversion succeeded but did not preserve the text. */
		#expect(encoded != Data(text.utf8))
		#expect(encoded.isEmpty == false)
	}

	// MARK: - Decoding

	nonisolated struct DecodeCase: Sendable { // nonisolated: value
		let primary: String.Encoding
		let fallback: String.Encoding
		let bytes: [UInt8]
		let text: String

		init(primary: String.Encoding, fallback: String.Encoding, _ bytes: [UInt8], _ text: String) {
			self.primary = primary
			self.fallback = fallback
			self.bytes = bytes
			self.text = text
		}
	}

	nonisolated static let decodeCases: [DecodeCase] = [ // nonisolated: let
		DecodeCase(primary: .utf8, fallback: .isoLatin1, [104, 105], "hi"),
		/* Valid UTF-8 is decoded by the primary encoding. */
		DecodeCase(primary: .utf8, fallback: .isoLatin1, [0xC3, 0xA9], "\u{00E9}"),
		/* A lone high byte is not UTF-8; Latin-1 reads it. */
		DecodeCase(primary: .utf8, fallback: .isoLatin1, [0xE9], "\u{00E9}"),
		/* Latin-1 is also the last resort when the fallback cannot decode. */
		DecodeCase(primary: .utf8, fallback: .ascii, [0xFF], "\u{00FF}"),
		DecodeCase(primary: .utf8, fallback: .ascii, [0x80], "\u{0080}"),
		DecodeCase(primary: .utf8, fallback: .ascii, [0xE9, 0x41], "\u{00E9}A"),
		/* The ladder ends at Latin-1: two UTF-8 bytes read as two of its own. */
		DecodeCase(primary: .ascii, fallback: .isoLatin1, [0xC3, 0xA9], "\u{00C3}\u{00A9}"),
		DecodeCase(primary: .utf8, fallback: .isoLatin1, [], ""),
	]

	@Test(arguments: Self.decodeCases)
	func decodesThroughTheFallbackLadder(testCase: DecodeCase) throws {
		let policy = Self.policy(primary: testCase.primary, fallback: testCase.fallback)
		let decoded = try #require(policy.decode(Data(testCase.bytes)))

		#expect(decoded == testCase.text)
	}

	/// Decoding never fails: Latin-1 accepts every byte sequence.
	@Test(arguments: [[0xFF] as [UInt8], [0x00], [0xFE, 0xFF], [0x80, 0x81, 0x82]])
	func decodingAlwaysProducesAString(bytes: [UInt8]) {
		let policy = Self.policy(primary: .utf8, fallback: .ascii)

		#expect(policy.decode(Data(bytes)) != nil)
	}

	// MARK: - UTF8ONLY

	nonisolated struct EncodingPair: Sendable { // nonisolated: value
		let primary: String.Encoding
		let fallback: String.Encoding

		init(_ primary: String.Encoding, _ fallback: String.Encoding) {
			self.primary = primary
			self.fallback = fallback
		}
	}

	@Test(arguments: [
		EncodingPair(.ascii, .isoLatin1),
		EncodingPair(.isoLatin1, .ascii),
		EncodingPair(.utf8, .utf8),
		EncodingPair(.japaneseEUC, .shiftJIS),
	])
	func utf8OnlyOverridesBothConfiguredEncodings(testCase: EncodingPair) {
		let policy = Self.policy(primary: testCase.primary, fallback: testCase.fallback, requiresUTF8: true)

		#expect(policy.primary == .utf8)
		#expect(policy.fallback == .utf8)
	}

	@Test
	func utf8OnlyEncodesTextThatAsciiCouldNotHold() throws {
		let policy = Self.policy(primary: .ascii, fallback: .ascii, requiresUTF8: true)
		let encoded = try #require(policy.encode("\u{2713}"))

		#expect(encoded == Data("\u{2713}".utf8))
	}
}

/// The encodings a client derives from its configuration and from ISUPPORT.
@MainActor
struct IRCClientTextEncodingClientCorpusTests {
	@Test
	func defaultsToUTF8WithALatin1Fallback() {
		let client = GLTTestClient()

		#expect(client.effectivePrimaryEncoding == .utf8)
		#expect(client.effectiveFallbackEncoding == .isoLatin1)
	}

	@Test
	func configuredEncodingsAreUsed() {
		let client = GLTTestClient(configDictionary: [
			"primaryEncoding": String.Encoding.isoLatin1.rawValue,
			"fallbackEncoding": String.Encoding.ascii.rawValue,
		])

		#expect(client.effectivePrimaryEncoding == .isoLatin1)
		#expect(client.effectiveFallbackEncoding == .ascii)
	}

	@Test
	func utf8OnlyServersPinBothEncodings() {
		let client = GLTTestClient(configDictionary: [
			"primaryEncoding": String.Encoding.isoLatin1.rawValue,
			"fallbackEncoding": String.Encoding.ascii.rawValue,
		])

		client.supportInfo.processConfigurationData("UTF8ONLY")

		#expect(client.effectivePrimaryEncoding == .utf8)
		#expect(client.effectiveFallbackEncoding == .utf8)
	}

	@Test(arguments: ["hello", "h\u{00E9}llo", "\u{2713} check", "\u{65E5}\u{672C}\u{8A9E}"])
	func roundTripsThroughTheCommonEncoding(text: String) throws {
		let client = GLTTestClient()
		let encoded = try #require(client.convert(toCommonEncoding: text))
		let decoded = try #require(client.convert(fromCommonEncoding: encoded))

		#expect(decoded == text)
	}
}
