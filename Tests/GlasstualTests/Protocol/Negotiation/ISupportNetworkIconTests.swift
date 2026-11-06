// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("ISUPPORT ICON")
struct ISupportNetworkIconTests {
	@Test("An http or https address is kept", arguments: [
		"https://example.org/icon.png",
		"http://example.org/icon.png",
		"HTTPS://example.org/a/b.webp",
	])
	func webAddressIsKept(_ value: String) {
		let support = ISupport()

		support.processConfigurationData("ICON=\(value)")

		#expect(support.networkIconURL == URL(string: value))
	}

	@Test("An address that is not a web address reads as no icon", arguments: [
		"file:///etc/passwd",
		"data:image/png;base64,AAAA",
		"ftp://example.org/icon.png",
		"example.org/icon.png",
		"https:///icon.png",
	])
	func otherAddressIsRefused(_ value: String) {
		let support = ISupport()

		support.processConfigurationData("ICON=\(value)")

		#expect(support.networkIconURL == nil)
	}

	@Test("An address longer than the limit is refused")
	func overlongAddressIsRefused() {
		let support = ISupport()
		let padding = String(repeating: "a", count: ISupportTokenParser.maximumNetworkIconURLLength)

		support.processConfigurationData("ICON=https://example.org/\(padding)")

		#expect(support.networkIconURL == nil)
	}

	@Test("A later invalid value withdraws the icon")
	func invalidValueWithdrawsTheIcon() {
		let support = ISupport()

		support.processConfigurationData("ICON=https://example.org/icon.png")
		support.processConfigurationData("ICON=file:///x")

		#expect(support.networkIconURL == nil)
	}

	@Test("A negated token withdraws the icon")
	func negatedTokenWithdrawsTheIcon() {
		let support = ISupport()

		support.processConfigurationData("ICON=https://example.org/icon.png")
		support.processConfigurationData("-ICON")

		#expect(support.networkIconURL == nil)
	}
}
