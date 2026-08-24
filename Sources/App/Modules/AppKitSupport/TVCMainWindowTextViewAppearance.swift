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

@objc(TVCMainWindowTextViewAppearance)
public final class MainWindowTextViewAppearance: ApplicationAppearance {
	@objc public private(set) var textViewInset: NSSize = .zero
	@objc public private(set) var textViewTextColor: NSColor?
	@objc public private(set) var textViewPlaceholderTextColor: NSColor?
	@objc public private(set) var textViewPreferredFontSize: TVCMainWindowTextViewFontSize = .normal
	@objc public private(set) var backgroundViewContentBorderPadding: CGFloat = 0

	@objc(initWithWindow:)
	public init?(window _: TVCMainWindow) {
		guard let appearanceLocation = Bundle.main.url(
			forResource: "TVCMainWindowTextViewAppearance",
			withExtension: "plist"
		) else {
			return nil
		}

		super.init(appearanceAt: appearanceLocation)

		guard let properties = appearanceProperties else {
			return nil
		}

		let textView = properties["Text View"] as? [String: Any] ?? [:]
		textViewInset = size(inGroup: textView, withKey: "inset")
		textViewTextColor = color(inGroup: textView, withKey: "normalTextColor")
		textViewPlaceholderTextColor = color(inGroup: textView, withKey: "placeholderTextColor")

		let backgroundView = properties["Background View"] as? [String: Any] ?? [:]
		backgroundViewContentBorderPadding = measurement(inGroup: backgroundView, withKey: "contentBorderPadding")

		flushAppearanceProperties()
	}

	@objc public func preferredTextViewFontChanged() -> Bool {
		textViewPreferredFontSize != TPCPreferences.mainTextViewFontSize()
	}

	@objc public var textViewPreferredFont: NSFont? {
		let preferredFontSize = TPCPreferences.mainTextViewFontSize()
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
