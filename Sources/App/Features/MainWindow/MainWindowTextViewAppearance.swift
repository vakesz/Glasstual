/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

/// The shape of `TVCMainWindowTextViewAppearance.plist`.
struct MainWindowTextViewAppearanceSchema: Decodable, Sendable {
	struct TextView: Decodable, Sendable {
		let inset: AppearanceSize
		let normalTextColor: AppearanceColor?
		let placeholderTextColor: AppearanceColor?
	}

	struct BackgroundView: Decodable, Sendable {
		let contentBorderPadding: Double
	}

	let textView: TextView
	let backgroundView: BackgroundView

	private enum CodingKeys: String, CodingKey {
		case textView = "Text View"
		case backgroundView = "Background View"
	}
}

public final class MainWindowTextViewAppearance: ApplicationAppearance {
	public private(set) var textViewInset: NSSize = .zero
	public private(set) var textViewTextColor: NSColor?
	public private(set) var textViewPlaceholderTextColor: NSColor?
	public private(set) var textViewPreferredFontSize: TVCMainWindowTextViewFontSize = .normal
	public private(set) var backgroundViewContentBorderPadding: CGFloat = 0

	@MainActor
	public init?() {
		super.init(applicationProperties: Self.currentApplicationProperties)

		guard let schema = AppearanceSchema.load(
			MainWindowTextViewAppearanceSchema.self,
			resource: "TVCMainWindowTextViewAppearance",
			appearanceName: appearanceName
		) else {
			return nil
		}

		textViewInset = schema.textView.inset.size
		textViewTextColor = schema.textView.normalTextColor?.color
		textViewPlaceholderTextColor = schema.textView.placeholderTextColor?.color
		backgroundViewContentBorderPadding = schema.backgroundView.contentBorderPadding
	}

	public func preferredTextViewFontChanged() -> Bool {
		textViewPreferredFontSize != TextualPreferences.mainTextViewFontSize()
	}

	/// Records the size it resolved, so `preferredTextViewFontChanged()` can
	/// tell whether the preference moved since the font was last handed out.
	public func makeTextViewPreferredFont() -> NSFont {
		let preferredFontSize = TextualPreferences.mainTextViewFontSize()
		textViewPreferredFontSize = preferredFontSize

		/* Sizes track the system text styles so they follow the
		 user's text size preferences rather than fixed point values. */
		switch preferredFontSize {
		case .large:
			return NSFont.preferredFont(forTextStyle: .title3, options: [:])
		case .extraLarge:
			return NSFont.preferredFont(forTextStyle: .title2, options: [:])
		case .humongous:
			return NSFont.preferredFont(forTextStyle: .title1, options: [:])
		default:
			return NSFont.preferredFont(forTextStyle: .body, options: [:])
		}
	}
}
