/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/// The Objective-C entry points the compiler cannot check for us.
///
/// Each selector here is one AppKit looks up by name and Swift does
/// not expose on its own: an optional requirement of a protocol the superclass
/// declares, or private SPI whose selector has no Swift spelling. Nothing about
/// the declaration says it has to reach the runtime, so removing the annotation
/// compiles, passes the suite, and takes the feature with it — which is exactly
/// what happened to all three of these. A selector a type declares itself needs
/// no test; these are not that.
@MainActor
@Suite("Objective-C entry points")
struct ObjCRuntimeEntryPointTests {
	/** Each sheet assigns itself as the window delegate programmatically. AppKit
	 invokes this optional protocol requirement through the Objective-C runtime;
	 without it the sheet never hears that it closed and never leaves the window
	 list. */
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
}
