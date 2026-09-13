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
	var proposedNickname: String

	/// The sheet submits `normalizedNickname`, so that is what is validated;
	/// validating the raw text let trimmed-away junk through.
	var validationError: String? {
		validator(normalizedNickname)
	}

	/// The refusal, once changing the nickname has been tried. Nothing is said
	/// before that: the field opens on the nickname already in use.
	var validationMessage: String? {
		submissionWasAttempted ? validationError : nil
	}

	private var submissionWasAttempted = false
	private let validator: Validator

	init(currentNickname: String, validator: @escaping Validator) {
		self.currentNickname = currentNickname
		proposedNickname = currentNickname
		self.validator = validator
	}

	var normalizedNickname: String {
		proposedNickname.firstToken
	}

	@discardableResult
	func validateForSubmission() -> Bool {
		submissionWasAttempted = true

		return validationError == nil
	}
}
