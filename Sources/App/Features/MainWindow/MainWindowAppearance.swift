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
 *********************************************************************** */

import AppKit

/** The main window's fixed metrics and colours.

 These were two property lists keyed by appearance name, decoded through a
 `Decodable` schema, a colour grammar and a loader. Each file held exactly one
 appearance and every value in it was a constant, so the whole path answered a
 question nobody asked: the window has one set of metrics, and this is it. */
nonisolated enum MainWindowAppearance { // nonisolated: value
	/// The size Reset Window gives back, before the window's own minimum
	/// content size is applied.
	static let defaultWindowSize = NSSize(width: 800, height: 474)

	/// The input field's text container inset.
	static let inputFieldInset = NSSize(width: 1, height: 2)

	/// What the input field draws typed text in.
	static var inputFieldTextColor: NSColor {
		.labelColor
	}

	/// What it draws its placeholder in while it is empty.
	static var inputFieldPlaceholderTextColor: NSColor {
		.placeholderTextColor
	}

	/// The vertical room the input bar's background adds around one line of
	/// text, which is what sets the bar's minimum height.
	static let contentBorderPadding: CGFloat = 23

	/// The input field's font for a text-size preference. The sizes track the
	/// system text styles so they follow the reader's text size preferences
	/// rather than fixed point values.
	@MainActor
	static func inputFieldFont(for size: MainWindowTextFontSize) -> NSFont {
		switch size {
		case .large:
			NSFont.preferredFont(forTextStyle: .title3, options: [:])
		case .extraLarge:
			NSFont.preferredFont(forTextStyle: .title2, options: [:])
		case .humongous:
			NSFont.preferredFont(forTextStyle: .title1, options: [:])
		default:
			NSFont.preferredFont(forTextStyle: .body, options: [:])
		}
	}
}
