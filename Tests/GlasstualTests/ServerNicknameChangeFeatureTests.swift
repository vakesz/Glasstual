/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

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
@Suite("Server nickname change sheet")
struct ServerNicknameChangeFeatureTests {
	@Test("The sheet's copy comes from the localized catalog")
	func contentUsesKeyedLocalizedCopy() {
		let content = ServerNicknameChangeContent.current

		#expect(content.currentNicknameLabel == "Current nickname:")
		#expect(content.newNicknameLabel == "New nickname:")
		#expect(content.changeButtonTitle == "Change Nickname")
		#expect(content.cancelButtonTitle == "Cancel")
		#expect(content.windowTitle == content.changeButtonTitle)
	}

	@Test("Validation runs on every keystroke but is only shown once the sheet is submitted")
	func modelValidatesContinuouslyAndPresentsErrorsOnlyOnSubmission() {
		let model = ServerNicknameChangeModel(currentNickname: "OldNick") { candidate in
			candidate == "NewNick" || candidate == "OldNick" ? nil : "Invalid nickname"
		}

		#expect(model.validationError == nil)
		#expect(model.isValidationMessagePresented == false)

		model.proposedNickname = "invalid"
		#expect(model.validationError == "Invalid nickname")
		#expect(model.isValidationMessagePresented == false)
		#expect(model.validateForSubmission() == false)
		#expect(model.isValidationMessagePresented)

		model.proposedNickname = "NewNick"
		#expect(model.validationError == nil)
		#expect(model.isValidationMessagePresented == false)
		#expect(model.validateForSubmission())
		#expect(model.normalizedNickname == "NewNick")
	}

	@Test("The sheet session keeps client identity and forwards its outcome")
	func sessionKeepsClientAndDelegateContracts() {
		let client = GLTTestClient()
		client.userNickname = "OldNick"
		let adapter = ServerChangeNicknameSheet(client: client)
		let clientPrototype: ClientScoped = adapter
		let delegate = ServerNicknameChangeDelegateSpy()

		adapter.delegate = delegate

		#expect(adapter.client === client)
		#expect(clientPrototype.clientId == client.uniqueIdentifier)
		adapter.ok(nil)
		#expect(delegate.acceptedNickname == "OldNick")

		adapter.sheetDidEnd(withReturnCode: 0)
		#expect(delegate.didClose)
	}
}
