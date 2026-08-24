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

@objc(TVCMainWindowAppearance)
public final class MainWindowAppearance: ApplicationAppearance {
	@objc public private(set) var textView: MainWindowTextViewAppearance!
	@objc public private(set) var defaultWindowSize: NSSize = .zero
	@objc public private(set) var channelViewOverlayDefaultBackgroundColorActiveWindow: NSColor?
	@objc public private(set) var channelViewOverlayDefaultBackgroundColorInactiveWindow: NSColor?

	@objc(initWithWindow:)
	public init?(window mainWindow: TVCMainWindow) {
		guard let appearanceLocation = Bundle.main.url(
			forResource: "TVCMainWindowAppearance",
			withExtension: "plist"
		) else {
			return nil
		}

		super.init(appearanceAt: appearanceLocation)

		defaultWindowSize = size(forKey: "defaultWindowSize")
		channelViewOverlayDefaultBackgroundColorActiveWindow = color(
			forKey: "channelViewOverlayDefaultBackgroundColor",
			forActiveWindow: true
		)
		channelViewOverlayDefaultBackgroundColorInactiveWindow = color(
			forKey: "channelViewOverlayDefaultBackgroundColor",
			forActiveWindow: false
		)

		guard let textView = MainWindowTextViewAppearance(window: mainWindow) else {
			return nil
		}

		self.textView = textView
		flushAppearanceProperties()
	}
}
