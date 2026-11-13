// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Where one question appears.
nonisolated enum PromptRoute: Equatable, Sendable {
	/// As an alert. `revealsMainWindow` brings a hidden main window forward
	/// for it, which only a question the reader just raised does.
	case dialog(revealsMainWindow: Bool)
	/// In the conversation of the chat item with this identifier.
	case inline(itemID: String)

	var itemID: String? {
		if case let .inline(itemID) = self {
			return itemID
		}
		return nil
	}
}

/** Which of the two forms a question takes.

 | Rule | Condition | Route |
 | --- | --- | --- |
 | R1 | the reader chose dialogs | dialog |
 | R2 | the question needs what only a dialog shows | dialog |
 | R3 | it was raised inside a sheet, a window or Settings | dialog |
 | R4 | there is no conversation to show it in | dialog |
 | R5 | otherwise | the conversation |

 Decided when the question is asked, so changing the setting moves the next
 question and never one already showing. */
nonisolated enum PromptRouting {
	static func route(
		style: InteractionStyle,
		allowsInline: Bool,
		origin: PromptOrigin,
		anchor itemID: String?,
		revealsMainWindow: Bool
	) -> PromptRoute {
		let dialog = PromptRoute.dialog(revealsMainWindow: revealsMainWindow)
		guard style == .conversation, allowsInline, origin != .guiSurface, let itemID else {
			return dialog
		}
		return .inline(itemID: itemID)
	}
}
