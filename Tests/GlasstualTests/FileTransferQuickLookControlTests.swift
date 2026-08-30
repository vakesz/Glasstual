/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import QuickLookUI
import Testing

/// `QLPreviewPanel.currentController` is whichever object took control through
/// the responder chain. For the file-transfer dialog that is its window, not
/// the dialog: the dialog is the window's delegate and never enters the chain.
/// The comparison used to be against the dialog, so it never matched and the
/// panel was neither ordered out on close nor reloaded on a selection change.
@Suite("File transfer Quick Look control")
struct FileTransferQuickLookControlTests {
	@Test("The window, not the dialog, is what the panel names as its controller")
	func theWindowIsWhatThePanelNamesAsItsController() {
		let window = NSWindow()
		let other = NSWindow()
		let delegate = NSObject()

		#expect(FileTransferDialog.previewPanel(controlledBy: window, is: window))
		#expect(FileTransferDialog.previewPanel(controlledBy: other, is: window) == false)
		#expect(FileTransferDialog.previewPanel(controlledBy: delegate, is: window) == false)
	}

	@Test("No controller, or no window, is not this dialog's panel")
	func noControllerOrNoWindowIsNotThisDialogsPanel() {
		let window = NSWindow()

		#expect(FileTransferDialog.previewPanel(controlledBy: nil, is: window) == false)
		#expect(FileTransferDialog.previewPanel(controlledBy: window, is: nil) == false)
	}
}
