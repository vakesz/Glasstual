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
@testable import Glasstual
import Testing

@Suite("Channel selection view nib")
@MainActor
struct ChannelSelectionViewControllerNibTests {
	/// TVCChannelSelectionView.xib connects an outlet named `outlineView`. Nib
	/// loading sets it through `setValue(_:forKey:)`, so a property under any
	/// other name raises NSUnknownKeyException while the nib loads.
	@Test("Loading the nib connects every outlet it declares")
	func nibLoadsAndConnectsOutlets() {
		let controller = ChannelSelectionViewController()
		#expect(controller.outlineView != nil)
	}

	@Test("The class is key-value coding compliant for the outlet the nib connects")
	func classIsCompliantForOutletKey() {
		let controller = ChannelSelectionViewController()
		#expect(controller.value(forKey: "outlineView") is NSOutlineView)
	}
}
