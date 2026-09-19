// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
struct ISupportPrefixTests {
	@Test("PREFIX replacement, empty value and withdrawal keep MODE parameters aligned")
	func prefixUpdatesReachModeParsing() {
		let info = supportInfo("CHANMODES=b,k,l,im PREFIX=(qov)~@+")
		info.processConfigurationData("PREFIX=(hv)%+")
		#expect(info.parseModes("+qhk alice key").map(\.modeParameter) == [nil, "alice", "key"])

		info.processConfigurationData("PREFIX=")
		#expect(info.parseModes("+hvk key").map(\.modeParameter) == [nil, nil, "key"])
		#expect(info.userModePrefixPairs.isEmpty)

		info.processConfigurationData("-PREFIX")
		#expect(info.parseModes("+hovk alice bob key").map(\.modeParameter) == [nil, "alice", "bob", "key"])
	}

	@Test(
		"PREFIX overlays CHANMODES regardless of token order and restores its underlying kind",
		arguments: [true, false]
	)
	func prefixOverlayPreservesChannelModeKinds(_ prefixFirst: Bool) {
		let tokens = ["PREFIX=(qov)~@+", "CHANMODES=b,k,l,qim"]
		let info = supportInfo((prefixFirst ? tokens : Array(tokens.reversed())).joined(separator: " "))
		#expect(info.parseModes("+qk alice key").map(\.modeParameter) == ["alice", "key"])

		info.processConfigurationData("PREFIX=(ov)@+")
		#expect(info.parseModes("+qk key").map(\.modeParameter) == [nil, "key"])

		info.processConfigurationData("PREFIX=(qov)~@+ -CHANMODES -PREFIX")
		#expect(info.parseModes("+qov alice bob").map(\.modeParameter) == [nil, "alice", "bob"])
	}

	private func supportInfo(_ configuration: String) -> ISupport {
		let supportInfo = ISupport()

		supportInfo.processConfigurationData(configuration)

		return supportInfo
	}

	/// `(ab)👍` has matching UTF-16 lengths but produces two mode symbols
	/// against a single prefix character, which used to trap on lookup.
	@Test
	func prefixLookupsStayPairedForEveryMode() {
		let supportInfo = supportInfo("PREFIX=(qaohv)~&@%+")

		#expect(supportInfo.userPrefix(forModeSymbol: "v") == "+")
		#expect(supportInfo.modeSymbol(forUserPrefix: "~") == "q")
		#expect(supportInfo.userModePrefixPairs.map(\.modeSymbol) == ["q", "a", "o", "h", "v"])
		#expect(supportInfo.userModePrefixPairs.map(\.character) == ["~", "&", "@", "%", "+"])
	}

	/// More prefix modes than the rank ceiling used to underflow `UInt`.
	@Test
	func rankDoesNotUnderflowWithMoreModesThanTheRankCeiling() {
		let ascii = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
		let latin = (0xC0 ... 0xFF).compactMap { UnicodeScalar($0).map(Character.init) }
		let symbols = Array((ascii + latin).prefix(105))

		#expect(symbols.count == 105)

		let token = "(" + String(symbols) + ")" + String(symbols)
		let supportInfo = supportInfo("PREFIX=" + token)

		#expect(supportInfo.rankForUserPrefix(withMode: String(symbols[0])) == 100)
		#expect(supportInfo.rankForUserPrefix(withMode: String(symbols[99])) == 1)
		#expect(supportInfo.rankForUserPrefix(withMode: String(symbols[104])) == 1)
		#expect(supportInfo.rankForUserPrefix(withMode: "\u{FFFD}") == 0)
	}
}
