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

public extension NSWindow {
	@objc(changeFrameToMinAndDisplay:)
	func changeFrame(toMinAndDisplay display: Bool) {
		changeFrame(toMinAndDisplay: display, animate: false)
	}

	@objc(changeFrameToMinAndDisplay:animate:)
	func changeFrame(toMinAndDisplay display: Bool, animate: Bool) {
		changeFrame(to: contentMinSize, display: display, animate: animate)
	}

	@objc(changeFrameTo:display:animate:)
	func changeFrame(to minSize: NSSize, display: Bool, animate: Bool) {
		let oldFrame = frame
		var newFrame = oldFrame

		let contentRect = contentRect(forFrameRect: newFrame)
		let bezelHeight = newFrame.size.height - contentRect.size.height

		newFrame.size.width = minSize.width
		newFrame.size.height = bezelHeight + minSize.height
		newFrame.origin.y = oldFrame.maxY - newFrame.size.height

		setFrame(newFrame, display: display, animate: animate)
	}
}

public extension NSView {
	/** The exact-class check this used to make rejected a subclass for no
	 reason, and the cast that followed it was then redundant. */
	@objc var mainWindow: TVCMainWindow? {
		window as? TVCMainWindow
	}

	@objc func addConstraintsToSuperviewToHugEdges() {
		guard let superview else {
			return
		}

		let constraints = [
			NSLayoutConstraint(
				item: self,
				attribute: .left,
				relatedBy: .equal,
				toItem: superview,
				attribute: .left,
				multiplier: 1.0,
				constant: 0.0
			),
			NSLayoutConstraint(
				item: self,
				attribute: .right,
				relatedBy: .equal,
				toItem: superview,
				attribute: .right,
				multiplier: 1.0,
				constant: 0.0
			),
			NSLayoutConstraint(
				item: self,
				attribute: .top,
				relatedBy: .equal,
				toItem: superview,
				attribute: .top,
				multiplier: 1.0,
				constant: 0.0
			),
			NSLayoutConstraint(
				item: self,
				attribute: .bottom,
				relatedBy: .equal,
				toItem: superview,
				attribute: .bottom,
				multiplier: 1.0,
				constant: 0.0
			),
		]

		superview.addConstraints(constraints)
	}

	/** Hugging the edges already pins all four of them. Adding the VFL
	 dimension constraints on top pinned the same edges a second time and
	 brought a zero-size constraint at priority 550 with them, so every pane
	 swap doubled the constraint count. */
	@objc(replaceFirstSubview:)
	func replaceFirstSubview(_ withSubview: NSView) {
		subviews.first?.removeFromSuperviewWithoutNeedingDisplay()
		addSubview(withSubview)
		withSubview.addConstraintsToSuperviewToHugEdges()
	}
}

public extension NSCell {
	@objc var window: NSWindow? {
		controlView?.window
	}

	@objc var mainWindow: TVCMainWindow? {
		controlView?.mainWindow
	}
}
