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

@MainActor
final class ServerNicknameChangeSheet: SheetSession, ClientScoped {
	private(set) var client: Client?
	private(set) var clientId: String?

	private let model: ServerNicknameChangeModel
	/// The nickname the person asked for.
	private let onSubmitNickname: (String) -> Void

	init(client: Client, onSubmitNickname: @escaping (String) -> Void) {
		let currentNickname = client.userNickname

		self.onSubmitNickname = onSubmitNickname
		self.client = client
		clientId = client.uniqueIdentifier
		model = ServerNicknameChangeModel(
			currentNickname: currentNickname,
			validator: Self.nicknameValidator(for: client)
		)

		super.init(window: nil)
		installSheet()
	}

	/** Checks a proposed nickname against what `client`'s server accepts.

	 The closure holds the client weakly, so the sheet's model is never what
	 keeps a connection alive. Once the client is gone the check falls back to
	 the syntax every server accepts. */
	static func nicknameValidator(for client: Client) -> ServerNicknameChangeModel.Validator {
		{ [weak client] candidate in
			if candidate.isEmpty {
				return ApplicationStrings.requiredField
			}

			let isNickname = if let client {
				(candidate as NSString).isHostmaskNickname(on: client)
			} else {
				(candidate as NSString).isHostmaskNickname
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

	func start() {
		startSheet()
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
			VStack(alignment: .leading, spacing: 6) {
				Text(.ServerProperties.changeButton)
					.font(.title2.weight(.semibold))
				Text(.ServerProperties.nicknameChangeDescription)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding([.horizontal, .top], 20)
			.padding(.bottom, 12)

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

			Divider()
			HStack(spacing: 8) {
				Spacer()
				Button(PromptStrings.Action.cancel, action: cancel)
					.keyboardShortcut(.cancelAction)
				Button(.ServerProperties.changeButton, action: submit)
					.keyboardShortcut(.defaultAction)
					.disabled(model.validationMessage != nil)
			}
			.padding(12)
		}
		.frame(minWidth: 400, idealWidth: 440, maxWidth: .infinity)
		.onAppear {
			nicknameFieldIsFocused = true
		}
	}
}
