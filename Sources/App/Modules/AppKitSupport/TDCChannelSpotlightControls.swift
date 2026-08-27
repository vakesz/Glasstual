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

@objc(TDCChannelSpotlightPanel)
public final class ChannelSpotlightPanel: NSPanel {
	override public init(
		contentRect: NSRect,
		styleMask style: NSWindow.StyleMask,
		backing bufferingType: NSWindow.BackingStoreType,
		defer flag: Bool
	) {
		super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
		prepareInitialState()
	}

	private func prepareInitialState() {
		styleMask.insert(.fullSizeContentView)
		titlebarAppearsTransparent = true
		titleVisibility = .hidden

		standardWindowButton(.closeButton)?.isHidden = true
		standardWindowButton(.miniaturizeButton)?.isHidden = true
		standardWindowButton(.zoomButton)?.isHidden = true
	}

	override public var isMovable: Bool {
		get { true }
		set {}
	}

	override public var isMovableByWindowBackground: Bool {
		get { true }
		set {}
	}

	override public var canBecomeKey: Bool {
		true
	}

	override public var canBecomeMain: Bool {
		true
	}
}

@objc(TDCChannelSpotlightTextField)
public final class ChannelSpotlightTextField: NSTextField {
	override public var mouseDownCanMoveWindow: Bool {
		true
	}
}

@objc(TDCChannelSpotlightImageView)
public final class ChannelSpotlightImageView: NSImageView {
	override public nonisolated func awakeFromNib() {
		super.awakeFromNib()

		MainActor.assumeIsolated {
			let symbol = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
			var configuration = NSImage.SymbolConfiguration(pointSize: 20.0, weight: .medium)
			configuration = configuration.applying(
				NSImage.SymbolConfiguration(hierarchicalColor: .secondaryLabelColor)
			)

			image = symbol?.withSymbolConfiguration(configuration)
			contentTintColor = .secondaryLabelColor
		}
	}

	override public var mouseDownCanMoveWindow: Bool {
		true
	}
}
