/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

private let cornerRadius: CGFloat = 10.0

@objc(TDCPreferencesGroupBox)
public final class PreferencesGroupBox: NSView {
	override public init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		prepareInitialState()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		prepareInitialState()
	}

	private func prepareInitialState() {
		wantsLayer = true
	}

	override public var isOpaque: Bool {
		false
	}

	override public func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override public func draw(_: NSRect) {
		/* Inset by half a point so the 1pt stroke is crisp and fully visible. */
		let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
		let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

		NSColor.quaternarySystemFill.setFill()
		path.fill()

		path.lineWidth = 1.0
		NSColor.separatorColor.setStroke()
		path.stroke()
	}
}
