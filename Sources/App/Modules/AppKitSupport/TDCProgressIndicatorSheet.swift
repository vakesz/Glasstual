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

@objc(TDCProgressIndicatorSheet)
@MainActor
public final class ProgressIndicatorSheet: SheetBase {
	@IBOutlet private var progressIndicator: NSProgressIndicator!

	@objc(initWithWindow:)
	override public init(window: NSWindow?) {
		precondition(window != nil)
		super.init(window: window)
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCProgressIndicatorSheet", owner: self, topLevelObjects: nil)
	}

	@objc public func start() {
		progressIndicator.startAnimation(nil)
		startSheet()
	}

	@objc public func stop() {
		progressIndicator.stopAnimation(nil)
		close()
	}
}
