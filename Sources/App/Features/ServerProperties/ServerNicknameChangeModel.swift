/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Observation

@MainActor
@Observable
final class ServerNicknameChangeModel {
	typealias Validator = (String) -> String?

	let currentNickname: String
	var proposedNickname: String {
		didSet {
			refreshValidation()
			isValidationMessagePresented = false
		}
	}

	private(set) var validationError: String?
	var isValidationMessagePresented = false

	private let validator: Validator

	init(currentNickname: String, validator: @escaping Validator) {
		self.currentNickname = currentNickname
		proposedNickname = currentNickname
		validationError = nil
		self.validator = validator
		refreshValidation()
	}

	var normalizedNickname: String {
		proposedNickname.firstToken
	}

	@discardableResult
	func validateForSubmission() -> Bool {
		refreshValidation()
		isValidationMessagePresented = validationError != nil

		return validationError == nil
	}

	private func refreshValidation() {
		// The sheet submits normalizedNickname, so that is what has to be
		// validated; validating the raw text let trimmed-away junk through.
		validationError = validator(normalizedNickname)
	}
}
