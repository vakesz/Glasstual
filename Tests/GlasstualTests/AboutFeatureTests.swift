/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
private final class AboutDialogDelegateSpy: NSObject, AboutDialogDelegate {
	private(set) var didClose = false

	func aboutDialogWillClose(_: AboutDialog) {
		didClose = true
	}
}

@MainActor
@Suite("About dialog")
struct AboutFeatureTests {
	@Test("The about panel's copy is built from the generated application metadata")
	func contentUsesGeneratedApplicationMetadataAndLocalizedCopy() {
		let content = AboutContent.current

		#expect(content.applicationName == ApplicationInfo.applicationNameWithoutVersion())
		#expect(content.versionDescription.contains(ApplicationInfo.applicationVersionShort()))
		#expect(content.upstreamAttribution.isEmpty == false)
		#expect(content.acknowledgementsButtonTitle.isEmpty == false)
		#expect(content.applicationIconAccessibilityLabel.contains(content.applicationName))
	}

	@Test("The prepared window is a fixed size, non-restorable host for the about view")
	func dialogPreparesAFixedSizeWindow() {
		let dialog = AboutDialog()

		let window = dialog.prepareWindow()

		#expect(dialog.window === window)
		#expect(window.delegate === dialog)
		#expect(window.contentViewController is NSHostingController<AboutView>)
		#expect(window.styleMask.contains(.closable))
		#expect(window.styleMask.contains(.fullSizeContentView))
		#expect(window.styleMask.contains(.resizable) == false)
		#expect(window.styleMask.contains(.miniaturizable) == false)
		#expect(window.isReleasedWhenClosed == false)
		#expect(window.isRestorable == false)
		#expect(window.tabbingMode == .disallowed)
		#expect(window.contentMinSize == NSSize(width: 218, height: 244))
		#expect(window.contentMaxSize == NSSize(width: 218, height: 244))
	}

	@Test("Closing the window tells the dialog's delegate")
	func closingTheWindowNotifiesTheDelegate() {
		let dialog = AboutDialog()
		let delegate = AboutDialogDelegateSpy()
		dialog.delegate = delegate
		_ = dialog.prepareWindow()

		dialog.windowWillClose(Notification(name: NSWindow.willCloseNotification))

		#expect(delegate.didClose)
	}
}
