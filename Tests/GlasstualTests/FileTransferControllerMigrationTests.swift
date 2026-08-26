/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import ObjectiveC.runtime
import XCTest

final class FileTransferControllerMigrationTests: XCTestCase {
	func testObjectiveCRuntimeNameRemainsStableForBindingsAndIRCClient() {
		XCTAssertEqual(
			NSStringFromClass(TDCFileTransferDialogTransferController.self),
			"TDCFileTransferDialogTransferController"
		)
	}

	func testFactorySelectorsRemainAvailableToIRCClient() throws {
		let metaClass = try XCTUnwrap(object_getClass(TDCFileTransferDialogTransferController.self))
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
}
