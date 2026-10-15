// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The marks the formatting parser leaves on the string it returns.

 They live on a transient `NSMutableAttributedString`: nothing persists them
 and the names carry no compatibility requirement. */
nonisolated enum IRCFormattingAttribute {
	static let foregroundColor = NSAttributedString.Key("GlasstualRendererForegroundColor")
	static let backgroundColor = NSAttributedString.Key("GlasstualRendererBackgroundColor")
	static let bold = NSAttributedString.Key("GlasstualRendererBold")
	static let italic = NSAttributedString.Key("GlasstualRendererItalic")
	static let monospace = NSAttributedString.Key("GlasstualRendererMonospace")
	static let strikethrough = NSAttributedString.Key("GlasstualRendererStrikethrough")
	static let underline = NSAttributedString.Key("GlasstualRendererUnderline")
}
