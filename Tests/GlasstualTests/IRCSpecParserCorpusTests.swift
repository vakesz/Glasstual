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
import GlasstualPluginKit
import Testing

/// The vendored `ircdocs/parser-tests` corpus, read out of the test bundle.
///
/// The corpus is the community's reading of RFC 1459 §2.3.1 and the IRCv3
/// message-tags grammar, so it is the closest thing to an executable
/// specification for the wire format.
enum IRCSpecCorpus {
	/// A bundle-resident anchor: Swift Testing suites are structs, so there is
	/// no test class to hand to `Bundle(for:)`.
	private final class Anchor {}

	struct MissingResource: Error, CustomStringConvertible {
		let name: String

		var description: String {
			"Corpus resource \(name).json is missing from the test bundle"
		}
	}

	private struct Corpus<Element: Decodable>: Decodable {
		let tests: [Element]
	}

	static func load<Case: Decodable>(_ name: String, as _: Case.Type) throws -> [Case] {
		let bundle = Bundle(for: Anchor.self)

		guard let url = bundle.url(forResource: name, withExtension: "json") else {
			throw MissingResource(name: name)
		}

		let data = try Data(contentsOf: url)

		return try JSONDecoder().decode(Corpus<Case>.self, from: data).tests
	}
}

/// `ircdocs/parser-tests` msg-split: splitting a line into tags, source, verb
/// and parameters. RFC 1459 §2.3.1 with the IRCv3 message-tags prelude.
struct IRCSpecMessageSplitCase: Decodable, CustomTestStringConvertible {
	struct Atoms: Decodable {
		let tags: [String: String]?
		let source: String?
		let verb: String?
		let params: [String]?
	}

	let input: String
	let atoms: Atoms

	var testDescription: String {
		input.debugDescription
	}
}

/// `ircdocs/parser-tests` msg-join: assembling atoms back into a line.
struct IRCSpecMessageJoinCase: Decodable, CustomTestStringConvertible {
	struct Atoms: Decodable {
		let tags: [String: String]?
		let source: String?
		let verb: String?
		let params: [String]?
	}

	let desc: String?
	let atoms: Atoms
	let matches: [String]

	var testDescription: String {
		desc ?? matches.first ?? "msg-join"
	}
}

/// `ircdocs/parser-tests` userhost-split: splitting a prefix into
/// nick/user/host, per RFC 2812 §2.3.1.
struct IRCSpecUserhostSplitCase: Decodable, CustomTestStringConvertible {
	struct Atoms: Decodable {
		let nick: String?
		let user: String?
		let host: String?
	}

	let source: String
	let atoms: Atoms

	var testDescription: String {
		source.debugDescription
	}
}

/// `ircdocs/parser-tests` mask-match: glob matching of `nick!user@host` masks.
struct IRCSpecMaskMatchCase: Decodable, CustomTestStringConvertible {
	let mask: String
	let matches: [String]?
	let fails: [String]?

	var testDescription: String {
		mask.debugDescription
	}
}

/// `ircdocs/parser-tests` validate-hostname.
struct IRCSpecHostnameCase: Decodable, CustomTestStringConvertible {
	let host: String
	let valid: Bool

	var testDescription: String {
		"\(host.debugDescription) -> \(valid)"
	}
}

@Suite("ircdocs/parser-tests corpus")
@MainActor
struct IRCSpecParserCorpusTests {
	// MARK: - msg-split

	nonisolated static let splitCases: [IRCSpecMessageSplitCase] =
		(try? IRCSpecCorpus.load("msg-split", as: IRCSpecMessageSplitCase.self)) ?? []

	@Test("The corpus files reached the test bundle")
	func corpusIsBundled() throws {
		#expect(try IRCSpecCorpus.load("msg-split", as: IRCSpecMessageSplitCase.self).count == 35)
		#expect(try IRCSpecCorpus.load("msg-join", as: IRCSpecMessageJoinCase.self).count == 18)
		#expect(try IRCSpecCorpus.load("userhost-split", as: IRCSpecUserhostSplitCase.self).count == 7)
		#expect(try IRCSpecCorpus.load("mask-match", as: IRCSpecMaskMatchCase.self).count == 6)
		#expect(try IRCSpecCorpus.load("validate-hostname", as: IRCSpecHostnameCase.self).count == 19)
	}

	/// RFC 1459 §2.3.1: `[':' prefix SPACE] command [params] CRLF`, read
	/// through `LineParser` the way the socket reader does.
	@Test("msg-split", arguments: splitCases)
	func lineSplitsIntoAtoms(_ testCase: IRCSpecMessageSplitCase) throws {
		let parsed = try #require(LineParser.parsedLine(fromLine: testCase.input))

		if let verb = testCase.atoms.verb {
			#expect(parsed.command.caseInsensitiveCompare(verb) == .orderedSame)
		}

		#expect(parsed.senderSection == testCase.atoms.source)
		#expect(parsed.parameters == (testCase.atoms.params ?? []))

		guard let expectedTags = testCase.atoms.tags else {
			#expect(parsed.messageTagSection == nil)
			return
		}

		let section = try #require(parsed.messageTagSection)

		#expect(MessageTagParser.parsedTags(fromSection: section).tags == expectedTags)
	}

	// MARK: - msg-join

	nonisolated static let joinCases: [IRCSpecMessageJoinCase] =
		(try? IRCSpecCorpus.load("msg-join", as: IRCSpecMessageJoinCase.self)) ?? []

	/// The corpus' candidate lines, rewritten the two ways a client's own line
	/// legitimately differs from them: it never writes a source, and RFC 1459
	/// §2.3 commands are case-insensitive, so `SendingMessage` upper-cases.
	private static func candidateLines(_ testCase: IRCSpecMessageJoinCase) -> [String] {
		testCase.matches.map { candidate in
			var prelude = ""
			var body = Substring(candidate)

			// The tag section, if any, stays exactly as the corpus wrote it.
			if body.first == "@", let space = body.firstIndex(of: " ") {
				prelude = String(body[...space])
				body = body[body.index(after: space)...]
			}

			if let source = testCase.atoms.source, body.hasPrefix(":\(source) ") {
				body = body.dropFirst(source.count + 2)
			}

			guard let verb = testCase.atoms.verb, body.hasPrefix(verb) else {
				return prelude + body
			}

			return prelude + verb.uppercased() + body.dropFirst(verb.count)
		}
	}

	/// The client's own encoder has to produce one of the encodings the corpus
	/// accepts for the same atoms. Cases whose trailing parameter is empty are
	/// covered separately: `SendingMessage` drops empty arguments by design.
	@Test("msg-join", arguments: joinCases.filter { $0.atoms.params?.last?.isEmpty != true })
	func atomsJoinIntoAnAcceptedLine(_ testCase: IRCSpecMessageJoinCase) throws {
		let verb = try #require(testCase.atoms.verb)
		let line = SendingMessage.string(
			command: verb,
			arguments: testCase.atoms.params,
			tags: testCase.atoms.tags
		)

		#expect(Self.candidateLines(testCase).contains(line))
	}

	/// Whatever encoding the client picks, reading it back has to recover the
	/// atoms it started from: msg-join and msg-split are two halves of one
	/// grammar.
	@Test(
		"msg-join round trips through msg-split",
		arguments: joinCases.filter { $0.atoms.params?.last?.isEmpty != true }
	)
	func joinedLineParsesBackIntoItsAtoms(_ testCase: IRCSpecMessageJoinCase) throws {
		let verb = try #require(testCase.atoms.verb)
		let line = SendingMessage.string(
			command: verb,
			arguments: testCase.atoms.params,
			tags: testCase.atoms.tags
		)
		let parsed = try #require(LineParser.parsedLine(fromLine: line))

		#expect(parsed.command.caseInsensitiveCompare(verb) == .orderedSame)
		#expect(parsed.parameters == (testCase.atoms.params ?? []))

		guard let expectedTags = testCase.atoms.tags else {
			#expect(parsed.messageTagSection == nil)
			return
		}

		let section = try #require(parsed.messageTagSection)

		#expect(MessageTagParser.parsedTags(fromSection: section).tags == expectedTags)
	}

	/// Documented deviation: `SendingMessage` skips empty arguments rather
	/// than writing the `:` that msg-join expects, so the last parameter is
	/// lost. Pinned here so the behaviour cannot drift unnoticed.
	@Test("msg-join: an empty trailing parameter is dropped, not written as ':'")
	func emptyTrailingParameterIsDropped() {
		#expect(SendingMessage.string(command: "foo", arguments: ["bar", "baz", ""]) == "FOO bar baz")
		#expect(SendingMessage.string(command: "AWAY", arguments: [""]) == "AWAY")
	}

	// MARK: - userhost-split

	nonisolated static let userhostCases: [IRCSpecUserhostSplitCase] =
		(try? IRCSpecCorpus.load("userhost-split", as: IRCSpecUserhostSplitCase.self)) ?? []

	/// RFC 2812 §2.3.1 `prefix = servername / (nickname [[ "!" user ] "@" host ])`.
	/// `IRCHostmask` only recognises the fully qualified form, so the corpus'
	/// partial sources are checked against what it does instead: reject.
	@Test("userhost-split", arguments: userhostCases)
	func hostmaskSplitsIntoAtoms(_ testCase: IRCSpecUserhostSplitCase) throws {
		let parsed = IRCHostmask(parsing: testCase.source)
		let isFullyQualified = testCase.atoms.user != nil && testCase.atoms.host != nil

		guard isFullyQualified else {
			#expect(parsed == nil, "partial sources are not recognised as hostmasks")
			return
		}

		let hostmask = try #require(parsed)

		#expect(hostmask.nickname == testCase.atoms.nick)
		#expect(hostmask.username == testCase.atoms.user)
		#expect(hostmask.address == testCase.atoms.host)
	}

	// MARK: - mask-match

	nonisolated static let maskCases: [IRCSpecMaskMatchCase] =
		(try? IRCSpecCorpus.load("mask-match", as: IRCSpecMaskMatchCase.self)) ?? []

	@Test("mask-match", arguments: maskCases)
	func masksMatchTheExpectedHostmasks(_ testCase: IRCSpecMaskMatchCase) {
		let matcher = AddressBookEntryMatcher(entryType: .ignore, hostmask: testCase.mask)

		for subject in testCase.matches ?? [] {
			#expect(matcher.matches(hostmask: subject), "\(testCase.mask) should match \(subject)")
		}

		for subject in testCase.fails ?? [] {
			#expect(
				matcher.matches(hostmask: subject) == false,
				"\(testCase.mask) should not match \(subject)"
			)
		}
	}

	// MARK: - validate-hostname

	nonisolated static let hostnameCases: [IRCSpecHostnameCase] =
		(try? IRCSpecCorpus.load("validate-hostname", as: IRCSpecHostnameCase.self)) ?? []

	/// The corpus notes that hostname validation is a server-side job and that
	/// clients should take whatever the server sends. Glasstual agrees: the
	/// only client-side check is that an address is non-empty and free of the
	/// characters that cannot survive the wire, so every corpus hostname the
	/// server could actually send has to be accepted.
	@Test("validate-hostname: no valid hostname is rejected", arguments: hostnameCases)
	func validHostnamesAreAccepted(_ testCase: IRCSpecHostnameCase) {
		guard testCase.valid else {
			return
		}

		#expect(IRCHostmask.isValidAddress(testCase.host))
	}

	/// The half of the corpus a client does enforce: an address that is empty
	/// or carries a space can never have come off the wire inside a prefix.
	@Test("validate-hostname: unusable hostnames are rejected", arguments: hostnameCases)
	func unusableHostnamesAreRejected(_ testCase: IRCSpecHostnameCase) {
		guard testCase.valid == false else {
			return
		}

		let unusable = testCase.host.isEmpty || testCase.host.contains(" ")

		#expect(IRCHostmask.isValidAddress(testCase.host) == (unusable == false))
	}
}
