// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("draft/metadata-2 capability values")
struct MetadataCapabilityValuesTests {
	@Test("Unknown tokens around a limit are ignored")
	func unknownTokensAreIgnored() {
		let values = MetadataCapabilityValues(capabilityValues: ["foo", "max-subs=50", "bar"])

		#expect(values.maximumSubscriptions == 50)
		#expect(values.beforeConnect == false)
		#expect(values.maximumKeys == nil)
		#expect(values.maximumValueBytes == nil)
	}

	@Test("Every limit is read, and before-connect is a flag")
	func everyLimit() {
		let values = MetadataCapabilityValues(
			capabilityValues: ["before-connect", "max-subs=25", "max-keys=10", "max-value-bytes=200"]
		)

		#expect(values.beforeConnect)
		#expect(values.maximumSubscriptions == 25)
		#expect(values.maximumKeys == 10)
		#expect(values.maximumValueBytes == 200)
	}

	@Test("A limit that is not a positive number is ignored", arguments: ["max-subs=0", "max-subs=x", "max-subs"])
	func invalidLimits(_ token: String) {
		#expect(MetadataCapabilityValues(capabilityValues: [token]).maximumSubscriptions == nil)
	}

	@Test(
		"Key names use lower-case letters, digits and _ . / -",
		arguments: [
			("display-name", true), ("im.xmpp", true), ("a/b_c", true), ("$url$", false),
			("", false), ("Avatar", false), ("with space", false),
		]
	)
	func keyGrammar(_ testCase: (key: String, valid: Bool)) {
		#expect(MetadataKey.isValid(testCase.key) == testCase.valid)
	}

	@Test("Both spellings of the invalid-target code read as one")
	func invalidTargetSpellings() {
		#expect(MetadataReplyCode(rawValue: "INVALID_TARGET") == .invalidTarget)
		#expect(MetadataReplyCode(rawValue: "TARGET_INVALID") == .invalidTarget)
		#expect(MetadataReplyCode(rawValue: "KEY_NOT_SET") == .keyNotSet)
		#expect(MetadataReplyCode(rawValue: "WHATEVER") == nil)
	}
}
