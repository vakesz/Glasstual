/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import QuickLookUI
import XCTest

@MainActor
final class FileTransferDialogMigrationTests: XCTestCase {
	func testObjectiveCRuntimeNamesRemainStableForNibLoading() {
		XCTAssertEqual(NSStringFromClass(FileTransferDialog.self), "TDCFileTransferDialog")
		XCTAssertEqual(NSStringFromClass(FileTransferDialogWindow.self), "TDCFileTransferDialogWindow")
	}

	func testPublicAndInternalObjectiveCSelectorsRemainAvailable() {
		let selectors = [
			"show:",
			"show:restorePosition:",
			"requestIPAddress",
			"requestIPAddress:",
			"clearIPAddress",
			"addReceiverForClient:nickname:address:port:filename:filesize:token:",
			"addSenderForClient:nickname:path:autoOpen:",
			"fileTransferExistsWithToken:",
			"fileTransferMatchingPort:client:peerNickname:filename:",
			"fileTransferSenderMatchingToken:client:peerNickname:filename:",
			"fileTransferReceiverMatchingToken:",
			"fileTransferWithUniqueIdentifier:",
			"updateClearButton",
			"updateMaintenanceTimer",
			"downloadDestinationURL",
			"setDownloadDestinationURL:",
			"startUsingDownloadDestinationURL",
		]

		for selector in selectors {
			XCTAssertTrue(FileTransferDialog.instancesRespond(to: NSSelectorFromString(selector)), selector)
		}
	}

	func testNibActionsRemainAvailable() {
		let selectors = [
			"hideWindow:",
			"clear:",
			"startTransferOfFile:",
			"stopTransferOfFile:",
			"removeTransferFromList:",
			"openReceivedFile:",
			"revealReceivedFileInFinder:",
			"quickLookFile:",
			"navigationSelectionDidChange:",
		]

		for selector in selectors {
			XCTAssertTrue(FileTransferDialog.instancesRespond(to: NSSelectorFromString(selector)), selector)
		}
	}

	func testWindowForwardsQuickLookResponderSelectors() {
		XCTAssertTrue(FileTransferDialogWindow
			.instancesRespond(to: #selector(NSResponder.acceptsPreviewPanelControl(_:))))
		XCTAssertTrue(FileTransferDialogWindow
			.instancesRespond(to: #selector(NSResponder.beginPreviewPanelControl(_:))))
		XCTAssertTrue(FileTransferDialogWindow.instancesRespond(to: #selector(NSResponder.endPreviewPanelControl(_:))))
	}
}
