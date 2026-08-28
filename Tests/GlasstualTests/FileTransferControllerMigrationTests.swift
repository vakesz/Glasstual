/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import ObjectiveC.runtime
import XCTest

@MainActor
final class FileTransferControllerMigrationTests: XCTestCase {
	func testObjectiveCRuntimeNameRemainsStableForBindingsAndIRCClient() {
		XCTAssertEqual(
			NSStringFromClass(TDCFileTransferDialogTransferController.self),
			"TDCFileTransferDialogTransferController"
		)
	}

	func testFactorySelectorsRemainAvailableToIRCClient() throws {
		let metaClass: AnyClass = try XCTUnwrap(object_getClass(TDCFileTransferDialogTransferController.self))
		let selectors = [
			"receiverForClient:nickname:address:port:filename:filesize:token:",
			"senderForClient:nickname:path:",
		]

		for selector in selectors {
			XCTAssertTrue(
				class_respondsToSelector(metaClass, NSSelectorFromString(selector)),
				selector
			)
		}
	}

	func testDialogAndDCCNegotiationSelectorsRemainAvailable() {
		let selectors = [
			"prepareForPermanentDestruction",
			"open",
			"openWithPathOrUserDownloads",
			"openWithPath:",
			"close",
			"closeAndPostNotification:",
			"sendTransferRequestToClient",
			"noteIPAddressLookupFailed",
			"noteIPAddressLookupSucceeded",
			"didReceiveSendRequest:hostPort:",
			"didReceiveResumeAccept:",
			"didReceiveResumeRequest:",
			"onMaintenanceTimer",
			"updateClearButton",
			"reloadStatusInformation",
		]

		for selector in selectors {
			XCTAssertTrue(
				TDCFileTransferDialogTransferController.instancesRespond(to: NSSelectorFromString(selector)),
				selector
			)
		}
	}

	func testBindingPropertiesRemainAvailable() {
		let selectors = [
			"client",
			"clientId",
			"transferTableCell",
			"setTransferTableCell:",
			"isResume",
			"isReversed",
			"isSender",
			"transferStatus",
			"totalFilesize",
			"processedFilesize",
			"currentRecord",
			"speedRecords",
			"errorMessageDescription",
			"path",
			"filename",
			"filePath",
			"fileURL",
			"hostAddress",
			"peerNickname",
			"transferToken",
			"uniqueIdentifier",
			"hostPort",
			"isActingAsClient",
			"isActingAsServer",
		]

		for selector in selectors {
			XCTAssertTrue(
				TDCFileTransferDialogTransferController.instancesRespond(to: NSSelectorFromString(selector)),
				selector
			)
		}
	}

	func testTransferEnumsPreserveLegacyRawValues() {
		XCTAssertEqual(FileTransferStatus.complete.rawValue, 0)
		XCTAssertEqual(FileTransferStatus.connecting.rawValue, 1)
		XCTAssertEqual(FileTransferStatus.fatalError.rawValue, 2)
		XCTAssertEqual(FileTransferStatus.initializing.rawValue, 3)
		XCTAssertEqual(FileTransferStatus.isListeningAsReceiver.rawValue, 4)
		XCTAssertEqual(FileTransferStatus.isListeningAsSender.rawValue, 5)
		XCTAssertEqual(FileTransferStatus.mappingListeningPort.rawValue, 6)
		XCTAssertEqual(FileTransferStatus.receiving.rawValue, 7)
		XCTAssertEqual(FileTransferStatus.recoverableError.rawValue, 8)
		XCTAssertEqual(FileTransferStatus.sending.rawValue, 9)
		XCTAssertEqual(FileTransferStatus.stopped.rawValue, 10)
		XCTAssertEqual(FileTransferStatus.waitingForLocalIPAddress.rawValue, 11)
		XCTAssertEqual(FileTransferStatus.waitingForReceiverToAccept.rawValue, 12)
		XCTAssertEqual(FileTransferStatus.waitingForResumeAccept.rawValue, 13)

		XCTAssertEqual(FileTransferSelection.all.rawValue, 0)
		XCTAssertEqual(FileTransferSelection.sending.rawValue, 1)
		XCTAssertEqual(FileTransferSelection.receiving.rawValue, 2)
	}
}
