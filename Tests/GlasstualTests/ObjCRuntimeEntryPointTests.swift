/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/// The Objective-C entry points the compiler cannot check for us.
///
/// Each selector here is one AppKit or WebKit looks up by name and Swift does
/// not expose on its own: an optional requirement of a protocol the superclass
/// declares, or private SPI whose selector has no Swift spelling. Nothing about
/// the declaration says it has to reach the runtime, so removing the annotation
/// compiles, passes the suite, and takes the feature with it — which is exactly
/// what happened to all three of these. A selector a type declares itself needs
/// no test; these are not that.
@MainActor
@Suite("Objective-C entry points")
struct ObjCRuntimeEntryPointTests {
	/** The nib wires each sheet as its window's delegate through an untyped
	 outlet, so nothing in the nib names this selector for `NibRuntimeNameTests`
	 to find. Without it the sheet never hears that it closed, and never leaves
	 the window list. */
	@Test("Every sheet that closes itself hears windowWillClose")
	func sheetsRespondToWindowWillClose() {
		let delegates: [NSObject.Type] = [
			AddressBookSheet.self,
			ChannelBanListSheet.self,
			ChannelPropertiesSheet.self,
			ChannelInviteSheet.self,
			ServerEndpointListSheet.self,
			ServerPropertiesSheet.self,
			ServerHighlightListSheet.self,
			ServerChangeNicknameSheet.self,
			HighlightEntrySheet.self,
			PreferencesUserStyleSheet.self,
			PreferencesController.self,
			ServerChannelListDialog.self,
			ChannelSpotlightController.self,
		]

		for delegate in delegates {
			#expect(
				delegate.instancesRespond(to: #selector(NSWindowDelegate.windowWillClose(_:))),
				"\(delegate) never hears that its window closed"
			)
		}
	}

	/** `_WKUIDelegatePrivate`. WebKit asks for the underscored selector and
	 there is no protocol to conform to, so the name has to be written out. */
	@Test("The channel view answers WebKit's private context-menu selector")
	func channelViewAnswersContextMenuSPI() {
		#expect(
			LogViewWebView.instancesRespond(to: NSSelectorFromString("_webView:contextMenu:forElement:"))
		)
	}

	/** A table asks its data source — not its delegate — where a drag may land.
	 The three methods satisfy optional requirements of `NSTableViewDataSource`,
	 which the diffable superclass declares rather than the subclass, so Swift
	 exposes none of them by itself. */
	@Test("The diffable data source answers the drag-and-drop selectors")
	func diffableDataSourceAnswersDragSelectors() {
		let selectors = [
			"tableView:pasteboardWriterForRow:",
			"tableView:validateDrop:proposedRow:proposedDropOperation:",
			"tableView:acceptDrop:row:dropOperation:",
		].map(NSSelectorFromString)

		for selector in selectors {
			#expect(
				ServerPropertiesTableDataSource.instancesRespond(to: selector),
				"the table cannot answer \(selector)"
			)
		}
	}
}
