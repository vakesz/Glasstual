/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Nickname change sheet validation")
struct ServerNicknameChangeValidationTests {
	/// Accepts only single-token nicknames, which is what makes the
	/// raw-versus-normalized distinction observable.
	private func makeModel(currentNickname: String = "mara") -> ServerNicknameChangeModel {
		ServerNicknameChangeModel(currentNickname: currentNickname) { proposed in
			proposed.contains(" ") || proposed.isEmpty ? "invalid" : nil
		}
	}

	@Test("The value that is validated is the value that is submitted")
	func validatesTheSubmittedValue() {
		let model = makeModel()

		model.proposedNickname = "  jonas  "

		#expect(model.normalizedNickname == "jonas")
		#expect(model.validateForSubmission())
	}

	@Test("Junk after the first token is rejected on its own merits")
	func rejectsInvalidNormalizedValue() {
		let model = makeModel()

		model.proposedNickname = "   "

		#expect(model.normalizedNickname.isEmpty)
		#expect(model.validateForSubmission() == false)
		#expect(model.isValidationMessagePresented)
	}
}
