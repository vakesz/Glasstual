// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Server nickname change sheet")
struct ServerNicknameChangeFeatureTests {
	@Test("The sheet's copy comes from the localized catalog")
	func sheetUsesKeyedLocalizedCopy() {
		#expect(String(localized: .ServerProperties.currentNicknameLabel) == "Current Nickname")
		#expect(String(localized: .ServerProperties.newNicknameLabel) == "New Nickname")
		#expect(String(localized: .ServerProperties.changeButton) == "Change Nickname")
		#expect(String(localized: .ServerProperties.nicknameChangeDescription).isEmpty == false)
		#expect(String(localized: .ServerProperties.newNicknamePlaceholder).isEmpty == false)
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

	/// The validator used to capture the connection strongly, so the sheet's
	/// model could keep a removed connection alive for as long as it lived.
	@Test("The nickname validator does not keep its connection alive")
	func validatorHoldsTheSessionWeakly() throws {
		var session: TestServerSession? = TestServerSession()
		weak let weakSession = session
		let validator = try ServerNicknameChangeSheet.nicknameValidator(for: #require(session))

		#expect(validator("alice") == nil)
		#expect(validator("") == ApplicationStrings.requiredField)

		session = nil

		try #require(weakSession == nil, "the validator must not be what keeps the connection alive")
		#expect(validator("alice") == nil)
		#expect(validator("not a nickname") == CommonValidationStrings.invalidNickname)
	}

	@Test("The sheet keeps session identity and reports the nickname it accepted")
	func sheetKeepsSessionAndReportsTheAcceptedNickname() {
		let session = TestServerSession()
		session.userNickname = "OldNick"
		var acceptedNickname: String?
		let sheet = ServerNicknameChangeSheet(session: session) { acceptedNickname = $0 }
		let sessionPrototype: SessionScoped = sheet

		#expect(sheet.session === session)
		#expect(sessionPrototype.sessionId == session.uniqueIdentifier)
		sheet.submit()
		#expect(acceptedNickname == "OldNick")
	}
}
