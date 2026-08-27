/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import XCTest

@MainActor
private final class AboutDialogDelegateSpy: NSObject, AboutDialogDelegate {
	private(set) var didClose = false

	func aboutDialogWillClose(_: AboutDialog) {
		didClose = true
	}
}

@MainActor
final class AboutFeatureTests: XCTestCase {
	func testContentUsesGeneratedApplicationMetadataAndLocalizedCopy() {
		let content = AboutContent.current

		XCTAssertEqual(content.applicationName, ApplicationInfo.applicationNameWithoutVersion())
		XCTAssertTrue(content.versionDescription.contains(ApplicationInfo.applicationVersionShort()))
		XCTAssertFalse(content.upstreamAttribution.isEmpty)
		XCTAssertFalse(content.acknowledgementsButtonTitle.isEmpty)
		XCTAssertTrue(content.applicationIconAccessibilityLabel.contains(content.applicationName))
	}

	func testDialogPreservesRuntimeAndWindowContracts() {
		XCTAssertEqual(NSStringFromClass(AboutDialog.self), "TDCAboutDialog")
		XCTAssertNotNil(NSProtocolFromString("TDCAboutDialogDelegate"))
		XCTAssertTrue(AboutDialog.instancesRespond(to: NSSelectorFromString("show")))
		XCTAssertTrue(AboutDialog.instancesRespond(to: NSSelectorFromString("close")))
		XCTAssertTrue(AboutDialog.instancesRespond(to: NSSelectorFromString("ok:")))
		XCTAssertTrue(AboutDialog.instancesRespond(to: NSSelectorFromString("cancel:")))
		XCTAssertTrue(AboutDialog.instancesRespond(to: NSSelectorFromString("displayAcknowledgements:")))
		XCTAssertTrue(AboutDialog.instancesRespond(to: NSSelectorFromString("windowWillClose:")))

		let dialog = AboutDialog()
		let delegate = AboutDialogDelegateSpy()
		dialog.delegate = delegate
		let window = dialog.prepareWindow()
		XCTAssertIdentical(dialog.window, window)

		XCTAssertTrue(window.delegate === dialog)
		XCTAssertTrue(window.contentViewController is NSHostingController<AboutView>)
		XCTAssertTrue(window.styleMask.contains(.closable))
		XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
		XCTAssertFalse(window.styleMask.contains(.resizable))
		XCTAssertFalse(window.styleMask.contains(.miniaturizable))
		XCTAssertFalse(window.isReleasedWhenClosed)
		XCTAssertFalse(window.isRestorable)
		XCTAssertEqual(window.tabbingMode, .disallowed)
		XCTAssertEqual(window.contentMinSize, NSSize(width: 218, height: 244))
		XCTAssertEqual(window.contentMaxSize, NSSize(width: 218, height: 244))

		dialog.windowWillClose(Notification(name: NSWindow.willCloseNotification))
		XCTAssertTrue(delegate.didClose)
	}
}
