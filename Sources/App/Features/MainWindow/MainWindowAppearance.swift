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

/// The shape of `TVCMainWindowAppearance.plist`.
struct MainWindowAppearanceSchema: Decodable, Sendable {
	let defaultWindowSize: AppearanceSize
	let channelViewOverlayDefaultBackgroundColor: AppearanceStatefulColor?
}

public final class MainWindowAppearance: ApplicationAppearance {
	public private(set) var textView: MainWindowTextViewAppearance
	public private(set) var defaultWindowSize: NSSize = .zero
	public private(set) var channelViewOverlayDefaultBackgroundColorActiveWindow: NSColor?
	public private(set) var channelViewOverlayDefaultBackgroundColorInactiveWindow: NSColor?

	@MainActor
	public init?() {
		guard let textView = MainWindowTextViewAppearance() else {
			return nil
		}
		self.textView = textView

		super.init(applicationProperties: Self.currentApplicationProperties)

		guard let schema = AppearanceSchema.load(
			MainWindowAppearanceSchema.self,
			resource: "TVCMainWindowAppearance",
			appearanceName: appearanceName
		) else {
			return nil
		}

		defaultWindowSize = schema.defaultWindowSize.size
		channelViewOverlayDefaultBackgroundColorActiveWindow =
			schema.channelViewOverlayDefaultBackgroundColor?.color(forActiveWindow: true)
		channelViewOverlayDefaultBackgroundColorInactiveWindow =
			schema.channelViewOverlayDefaultBackgroundColor?.color(forActiveWindow: false)
	}
}
