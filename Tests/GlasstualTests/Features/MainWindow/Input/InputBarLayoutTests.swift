// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Input bar layout")
struct InputBarLayoutTests {
	@Test("The accessory strip reserves room for exactly the rows that are showing")
	func accessoryHeight() {
		#expect(InputBarLayout.accessoryHeight(replyVisible: false, typingVisible: false) == 0)
		let reply = InputBarLayout.accessoryHeight(replyVisible: true, typingVisible: false)
		let typing = InputBarLayout.accessoryHeight(replyVisible: false, typingVisible: true)
		#expect(reply == InputBarLayout.replyBannerHeight)
		#expect(typing == InputBarLayout.typingRowHeight)
		#expect(InputBarLayout.accessoryHeight(replyVisible: true, typingVisible: true) == reply + typing + UISpacing.tight)
	}

	@Test("Accessory rows are tall enough for a line of their text")
	func rowsFitTheirText() {
		let line = TextLineMetrics.lineHeight(for: .preferredFont(forTextStyle: .subheadline))
		#expect(InputBarLayout.replyBannerHeight > line)
		#expect(InputBarLayout.typingRowHeight > line)
	}

	@Test("The capsule's measurements agree with the container they describe")
	func capsuleMeasurements() {
		#expect(InputBarLayout.hostInitialHeight == InputBarLayout.fieldBorderPadding - InputBarLayout.fieldInset.height * 2
			+ InputBarLayout.minimumTextHeight)
	}
}
