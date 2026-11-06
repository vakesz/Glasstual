// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// How the values of ISUPPORT tokens are read, on their own and without a session.
struct ISupportTokenParserTests {
	// MARK: - Escapes

	@Test("A hexadecimal escape names a byte, wherever it falls", arguments: [
		("Example\\x20Network", "Example Network"),
		("\\x20", " "),
		("trailing\\x20", "trailing "),
		("a\\x5Cb", "a\\b"),
		("a\\x5cb", "a\\b"),
		("caf\\xC3\\xA9", "café"),
		("no escapes", "no escapes"),
	])
	func escapesAreDecoded(_ written: String, _ expected: String) {
		#expect(ISupportTokenParser.unescapedValue(Substring(written)) == expected)
	}

	@Test("Something that is not a complete escape is kept as written", arguments: [
		"\\x2", "\\x", "\\", "\\x2g", "\\xg2", "\\y20", "end\\x2",
	])
	func incompleteEscapesAreKept(_ written: String) {
		#expect(ISupportTokenParser.unescapedValue(Substring(written)) == written)
	}

	@Test("Escaped bytes that are not UTF-8 are kept as sent")
	func invalidUTF8IsKept() {
		#expect(ISupportTokenParser.unescapedValue("\\xFF\\xFE") == "\\xFF\\xFE")
	}

	// MARK: - Counted entries

	@Test("CHANLIMIT keys each prefix, and an entry without a usable shape says nothing")
	func channelLimits() {
		#expect(ISupportTokenParser.channelLimits(from: "#:25,&!:10") == ["#": 25, "&": 10, "!": 10])
		#expect(ISupportTokenParser.channelLimits(from: ":5,#,&:abc") == ["&": 0])
		#expect(ISupportTokenParser.channelLimits(from: "").isEmpty)
		#expect(ISupportTokenParser.channelLimits(from: "#:-1") == ["#": 0])
	}

	@Test("TARGMAX keys are upper-cased, and an empty limit reads as none")
	func maximumTargets() {
		#expect(
			ISupportTokenParser.maximumTargets(from: "privmsg:4,NOTICE:,Kick:1")
				== ["PRIVMSG": 4, "NOTICE": 0, "KICK": 1]
		)
	}

	@Test("MAXLIST leaves out a mode with no positive limit")
	func maximumListEntries() {
		#expect(ISupportTokenParser.maximumListEntries(from: "beI:100,q:0,k:") == ["b": 100, "e": 100, "I": 100])
	}

	// MARK: - PREFIX

	@Test("PREFIX pairs each mode with its character in order")
	func userPrefix() {
		let configuration = ISupportTokenParser.userPrefixConfiguration(from: "(qaohv)~&@%+")

		#expect(configuration == ISupportPrefixConfig(modeSymbols: ["q", "a", "o", "h", "v"], characters: ["~", "&", "@", "%", "+"]))
	}

	@Test("A PREFIX that does not pair up is refused", arguments: [
		"(ov)@", "(o)@+", "ov@+", "()", "(", "x(ov)@+", "(ov)", "(ab)\u{1F44D}", "",
	])
	func malformedPrefix(_ token: String) {
		#expect(ISupportTokenParser.userPrefixConfiguration(from: token) == nil)
	}

	// MARK: - EXTBAN

	@Test("EXTBAN splits its prefix from its types", arguments: [
		("~,qjm", "~" as String?, ["q", "j", "m"]),
		("$$,a", "$$", ["a"]),
		(",abc", nil, ["a", "b", "c"]),
		("abc", nil, ["a", "b", "c"]),
		("", nil, []),
		("~,", "~", []),
	])
	func extendedBan(_ token: String, _ prefix: String?, _ types: [String]) {
		#expect(ISupportTokenParser.extendedBanConfiguration(from: token) == ISupportExtendedBanConfig(prefix: prefix, types: types))
	}

	// MARK: - CHANMODES

	@Test("CHANMODES groups A to D are classified and later groups ignored")
	func channelModes() {
		let kinds = ISupportTokenParser.channelModeKinds(from: "be,k,l,imnt,xyz", merging: [:])

		#expect(kinds["b"] == .list)
		#expect(kinds["k"] == .setting)
		#expect(kinds["l"] == .settingWhenSet)
		#expect(kinds["t"] == .flag)
		#expect(kinds["x"] == nil)
	}

	@Test("A later CHANMODES overrides a mode it names and keeps the rest")
	func channelModesMerge() {
		let kinds = ISupportTokenParser.channelModeKinds(from: ",k,,", merging: ["k": .flag, "o": .userPrefix])

		#expect(kinds["k"] == .setting)
		#expect(kinds["o"] == .userPrefix)
	}
}
