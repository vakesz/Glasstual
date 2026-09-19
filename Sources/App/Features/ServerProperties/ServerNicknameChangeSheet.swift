// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Observation
import SwiftUI

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

	/// The refusal, once changing the nickname has been tried.
	var validationMessage: String? {
		submission.shown(validationError)
	}

	private var submission = SubmissionGate()
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
		submission.attempt()

		return validationError == nil
	}
}

@MainActor
final class ServerNicknameChangeSheet: SheetSession, SessionScoped {
	private(set) var session: ServerSession?
	private(set) var sessionId: String?

	private let model: ServerNicknameChangeModel
	/// The nickname the person asked for.
	private let onSubmitNickname: (String) -> Void

	init(session: ServerSession, onSubmitNickname: @escaping (String) -> Void) {
		let currentNickname = session.userNickname

		self.onSubmitNickname = onSubmitNickname
		self.session = session
		sessionId = session.uniqueIdentifier
		model = ServerNicknameChangeModel(
			currentNickname: currentNickname,
			validator: Self.nicknameValidator(for: session)
		)

		super.init(window: nil)
		installSheet()
	}

	/** Checks a proposed nickname against what `session`'s server accepts.

	 The closure holds the session weakly, so the sheet's model is never what
	 keeps a connection alive. Once the session is gone the check falls back to
	 the syntax every server accepts. */
	static func nicknameValidator(for session: ServerSession) -> ServerNicknameChangeModel.Validator {
		{ [weak session] candidate in
			if candidate.isEmpty {
				return ApplicationStrings.requiredField
			}

			let isNickname = if let session {
				candidate.isHostmaskNickname(on: session)
			} else {
				candidate.isHostmaskNickname
			}

			return isNickname ? nil : CommonValidationStrings.invalidNickname
		}
	}

	private func installSheet() {
		let rootView = ServerNicknameChangeView(
			model: model,
			submit: { [weak self] in
				self?.submit()
			},
			cancel: { [weak self] in
				self?.cancel()
			}
		)
		setContent(rootView)
	}

	override func submit() {
		guard model.validateForSubmission() else {
			return
		}

		onSubmitNickname(model.normalizedNickname)

		super.submit()
	}
}

@MainActor
struct ServerNicknameChangeView: View {
	@Bindable var model: ServerNicknameChangeModel

	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var nicknameFieldIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			SheetHeading(
				.ServerProperties.changeButton,
				subtitle: Text(.ServerProperties.nicknameChangeDescription)
			)

			Form {
				Section {
					LabeledContent(.ServerProperties.currentNicknameLabel, value: model.currentNickname)
						.textSelection(.enabled)

					LabeledContent(.ServerProperties.newNicknameLabel) {
						TextField(.ServerProperties.newNicknamePlaceholder, text: $model.proposedNickname)
							.labelsHidden()
							.focused($nicknameFieldIsFocused)
							.accessibilityLabel(.ServerProperties.newNicknameLabel)
							.onSubmit(submit)
					}

					if let message = model.validationMessage {
						ValidationMessageLabel(message)
					}
				}
			}
			.formStyle(.grouped)

			SheetActions(
				confirmTitle: Text(.ServerProperties.changeButton),
				confirmIsDisabled: model.validationMessage != nil,
				confirm: submit,
				cancel: cancel
			)
		}
		.frame(minWidth: 400, idealWidth: 440, maxWidth: .infinity)
		.onAppear {
			nicknameFieldIsFocused = true
		}
	}
}
