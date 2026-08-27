/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

final class FileTransferDialogSocketMigrationTests: XCTestCase {
	func testObjectiveCRuntimeNamesRemainStable() {
		XCTAssertEqual(NSStringFromClass(FileTransferDialogSocket.self), "TDCFileTransferDialogSocket")
		XCTAssertEqual(
			NSStringFromProtocol(FileTransferDialogSocketDelegate.self),
			"TDCFileTransferDialogSocketDelegate"
		)
	}

	func testObjectiveCSelectorsRemainAvailable() {
		let selectors = [
			"initWithDelegate:delegateQueue:",
			"errorWithCode:description:",
			"listenOnPortRangeFrom:to:",
			"connectToHost:port:viaInterface:timeout:",
			"readData",
			"writeData:timeout:",
			"disconnect",
		]

		for selector in selectors {
			if selector.hasPrefix("errorWithCode:") {
				XCTAssertTrue(FileTransferDialogSocket.responds(to: NSSelectorFromString(selector)), selector)
			} else {
				XCTAssertTrue(FileTransferDialogSocket.instancesRespond(to: NSSelectorFromString(selector)), selector)
			}
		}
	}

	func testErrorFactoryPreservesDomainCodeAndDescription() {
		let error = FileTransferDialogSocket.error(
			withCode: .writeTimeout,
			description: "Write operation timed out"
		)

		XCTAssertEqual(error.domain, TDCFileTransferDialogSocketErrorDomain)
		XCTAssertEqual(error.code, FileTransferDialogSocketError.writeTimeout.rawValue)
		XCTAssertEqual(error.localizedDescription, "Write operation timed out")
	}
}
