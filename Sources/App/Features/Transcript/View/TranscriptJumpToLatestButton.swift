// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** Takes the reader back to the newest line. It is the same command the View
 menu carries, offered where the reader is actually looking.

 A floating control over the text, so it is glass; the glass button sizes
 itself from its control size, as the system's own floating buttons do. */
struct TranscriptJumpToLatestButton: View {
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Label(String(localized: .Transcript.menuNavigationJumpToPresent), systemImage: "arrow.down.to.line")
				.labelStyle(.iconOnly)
		}
		.buttonStyle(.glass)
		.buttonBorderShape(.circle)
		.controlSize(.large)
		.help(Text(.Transcript.menuNavigationJumpToPresent))
	}
}
