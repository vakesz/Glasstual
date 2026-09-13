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
	@objc(serverChangeNicknameSheet:didInputNickname:)
	func serverChangeNicknameSheet(
		_: ServerChangeNicknameSheet,
		didInputNickname nickname: String
	) {
		acceptedNickname = nickname
	}
}

@MainActor
@Suite("Server nickname change sheet")
struct ServerNicknameChangeFeatureTests {
	@Test("The sheet's copy comes from the localized catalog")
	func sheetUsesKeyedLocalizedCopy() {
		#expect(ServerNicknameChangeStrings.currentNicknameLabel == "Current Nickname")
		#expect(ServerNicknameChangeStrings.newNicknameLabel == "New Nickname")
		#expect(ServerNicknameChangeStrings.changeButtonTitle == "Change Nickname")
		#expect(ServerNicknameChangeStrings.changeDescription.isEmpty == false)
		#expect(ServerNicknameChangeStrings.newNicknamePlaceholder.isEmpty == false)
	}

	@Test("Validation runs on every keystroke but is only shown once the sheet is submitted")
	func modelValidatesContinuouslyAndPresentsErrorsOnlyOnSubmission() {
		let model = ServerNicknameChangeModel(currentNickname: "OldNick") { candidate in
			candidate == "NewNick" || candidate == "OldNick" ? nil : "Invalid nickname"
		}

		#expect(model.validationError == nil)
		#expect(model.validationMessage == nil)

		model.proposedNickname = "invalid"
		#expect(model.validationError == "Invalid nickname")
		#expect(model.validationMessage == nil)
		#expect(model.validateForSubmission() == false)
		#expect(model.validationMessage == "Invalid nickname")

		model.proposedNickname = "NewNick"
		#expect(model.validationError == nil)
		#expect(model.validationMessage == nil)
		#expect(model.validateForSubmission())
		#expect(model.normalizedNickname == "NewNick")
	}

	@Test("The sheet session keeps client identity and forwards its outcome")
	func sessionKeepsClientAndDelegateContracts() {
		let client = TestClient()
		client.userNickname = "OldNick"
		let adapter = ServerChangeNicknameSheet(client: client)
		let clientPrototype: ClientScoped = adapter
		let delegate = ServerNicknameChangeDelegateSpy()

		adapter.delegate = delegate

		#expect(adapter.client === client)
		#expect(clientPrototype.clientId == client.uniqueIdentifier)
		adapter.submit()
		#expect(delegate.acceptedNickname == "OldNick")
	}
}
