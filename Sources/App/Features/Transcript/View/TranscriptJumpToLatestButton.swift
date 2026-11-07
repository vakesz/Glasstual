// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** Takes the reader back to the newest line. It is the same command the View
 menu carries, offered where the reader is actually looking. */
struct TranscriptJumpToLatestButton: View {
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: "arrow.down.to.line")
				.font(.body.weight(.semibold))
				.frame(
					width: TranscriptMetrics.jumpToLatestButtonSize,
					height: TranscriptMetrics.jumpToLatestButtonSize
				)
		}
		.buttonStyle(.glass)
		.buttonBorderShape(.circle)
		.accessibilityLabel(Text(.Transcript.menuNavigationJumpToPresent))
		.help(Text(.Transcript.menuNavigationJumpToPresent))
	}
}
