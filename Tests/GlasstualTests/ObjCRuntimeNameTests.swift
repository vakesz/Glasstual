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
import CocoaExtensions
@testable import Glasstual
import Testing

/// The Objective-C names something outside the compiler depends on and no nib
/// mentions. `NibRuntimeNameTests` sweeps the nibs and checks every class,
/// outlet, action and binding they name, so the only entries left here are the
/// ones that survive for a reason a nib cannot express: an archive on disk, a
/// saved window frame, and the mIRC palette, whose indices are wire format
/// rather than a design choice.
///
/// Nothing else belongs here. A test that asserts a type conforms to a protocol,
/// responds to a selector it declares, or has the raw value written next to its
/// declaration restates the compiler and fails on every rename.
@Suite("Objective-C runtime names")
@MainActor
struct ObjCRuntimeNameTests {
	/// `NSKeyedArchiver` writes the class name into every blob in the historic
	/// log store, so an installation that upgrades has to keep reading the name
	/// its existing rows were written with.
	@Test("The archived log line keeps the runtime name its blobs were written with")
	func archivedLogLineKeepsItsRuntimeName() {
		#expect(NSStringFromClass(LogLineArchive.self) == "TVCLogLine")
	}

	/// A window's saved frame is keyed by these strings in the user's defaults.
	/// They used to come from `NSStringFromClass`; they are written down now, and
	/// this is what stops one being edited without meaning to.
	@Test("A window's saved-frame key keeps the string already on disk")
	func windowStateKeysArePinned() {
		#expect(WindowStateKey.preferences.rawValue == "TDCPreferencesController")
		#expect(WindowStateKey.serverChannelList.rawValue == "TDCServerChannelListDialog")
		#expect(WindowStateKey.about.rawValue == "TDCAboutDialog")
		#expect(WindowStateKey.channelSpotlight.rawValue == "TDCChannelSpotlightController")
		#expect(WindowStateKey.fileTransfers.rawValue == "TDCFileTransferDialog")
	}

	/// mIRC colour codes index this table, so the order is protocol, not
	/// presentation: colour 0 is white and colour 1 is black on every network.
	@Test("The mIRC palette keeps its 99 entries in wire order")
	func formatterPaletteIsPinned() {
		#expect(NSColor.formatterColors.count == 99)
		#expect(NSColor.formatterWhiteColor == NSColor.formatterColors[0])
		#expect(NSColor.formatterBlackColor == NSColor.formatterColors[1])
		#expect(NSColor.formatterLightGrayColor == NSColor.formatterColors[15])
	}
}
