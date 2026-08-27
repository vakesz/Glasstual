/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import XCTest

@MainActor
private final class ServerNicknameChangeDelegateSpy: NSObject, ServerChangeNicknameSheetDelegate {
	private(set) var acceptedNickname: String?
	private(set) var didClose = false

	@objc(serverChangeNicknameSheet:didInputNickname:)
	func serverChangeNicknameSheet(
		_: ServerChangeNicknameSheet,
		didInputNickname nickname: String
	) {
		acceptedNickname = nickname
	}

	@objc(serverChangeNicknameSheetWillClose:)
	func serverChangeNicknameSheetWillClose(_: ServerChangeNicknameSheet) {
		didClose = true
	}
}

@MainActor
final class ServerNicknameChangeFeatureTests: XCTestCase {
	func testContentUsesKeyedLocalizedCopy() {
		let content = ServerNicknameChangeContent.current

		XCTAssertEqual(content.currentNicknameLabel, "Current nickname:")
		XCTAssertEqual(content.newNicknameLabel, "New nickname:")
		XCTAssertEqual(content.changeButtonTitle, "Change Nickname")
		XCTAssertEqual(content.cancelButtonTitle, "Cancel")
		XCTAssertEqual(content.windowTitle, content.changeButtonTitle)
	}

	func testModelValidatesContinuouslyAndPresentsErrorsOnlyOnSubmission() {
		let model = ServerNicknameChangeModel(currentNickname: "OldNick") { candidate in
			candidate == "NewNick" || candidate == "OldNick" ? nil : "Invalid nickname"
		}

		XCTAssertNil(model.validationError)
		XCTAssertFalse(model.isValidationMessagePresented)

		model.proposedNickname = "invalid"
		XCTAssertEqual(model.validationError, "Invalid nickname")
		XCTAssertFalse(model.isValidationMessagePresented)
		XCTAssertFalse(model.validateForSubmission())
		XCTAssertTrue(model.isValidationMessagePresented)

		model.proposedNickname = "NewNick"
		XCTAssertNil(model.validationError)
		XCTAssertFalse(model.isValidationMessagePresented)
		XCTAssertTrue(model.validateForSubmission())
		XCTAssertEqual(model.normalizedNickname, "NewNick")
	}

	func testRuntimeSheetContractSurvivesWithoutANib() {
		XCTAssertEqual(NSStringFromClass(ServerChangeNicknameSheet.self), "TDCServerChangeNicknameSheet")
		XCTAssertNotNil(NSProtocolFromString("TDCServerChangeNicknameSheetDelegate"))
		XCTAssertNil(Bundle.main.path(forResource: "TDCServerChangeNicknameSheet", ofType: "nib"))

		for selectorName in [
			"initWithClient:",
			"start",
			"ok:",
			"cancel:",
			"okOrError",
			"windowWillClose:",
		] {
			XCTAssertTrue(
				ServerChangeNicknameSheet.instancesRespond(to: NSSelectorFromString(selectorName)),
				selectorName
			)
		}
	}

	func testAdapterKeepsClientWindowAndDelegateContracts() {
		let client = GLTTestClient()
		client.userNickname = "OldNick"
		let adapter = ServerChangeNicknameSheet(client: client)
		let clientPrototype: TDCClientPrototype = adapter
		let delegate = ServerNicknameChangeDelegateSpy()

		adapter.delegate = delegate

		XCTAssertIdentical(adapter.client, client)
		XCTAssertEqual(clientPrototype.clientId, client.uniqueIdentifier)
		XCTAssertTrue(adapter.sheet.delegate === adapter)
		XCTAssertTrue(adapter.sheet.contentViewController is NSHostingController<ServerNicknameChangeView>)
		XCTAssertFalse(adapter.sheet.styleMask.contains(.resizable))
		XCTAssertFalse(adapter.sheet.isReleasedWhenClosed)
		XCTAssertFalse(adapter.sheet.isRestorable)
		XCTAssertEqual(adapter.sheet.tabbingMode, .disallowed)
		XCTAssertEqual(adapter.sheet.contentMinSize, NSSize(width: 350, height: 131))
		XCTAssertEqual(adapter.sheet.contentMaxSize, NSSize(width: 350, height: 131))

		adapter.ok(nil)
		XCTAssertEqual(delegate.acceptedNickname, "OldNick")

		adapter.windowWillClose(Notification(name: NSWindow.willCloseNotification))
		XCTAssertTrue(delegate.didClose)
	}
}
