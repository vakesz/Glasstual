// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The Register Account sheet: the form, the code step and the result.
@MainActor
struct AccountRegistrationView: View {
	@Bindable var model: AccountRegistrationModel

	let stop: () -> Void
	let cancel: () -> Void

	@FocusState private var focusedField: AccountRegistrationField?
	@FocusState private var passwordConfirmationIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			SheetHeading(
				.AccountRegistrationSheet.title,
				subtitle: Text(.AccountRegistrationSheet.subtitle(model.networkName))
			)

			Form {
				switch model.phase {
				case .form, .submitting:
					formSections
				case .code, .verifying:
					codeSection
				case let .succeeded(account, credentialsSaved):
					successSection(account: account, credentialsSaved: credentialsSaved)
				}
			}
			.formStyle(.grouped)
			.disabled(model.phase == .submitting || model.phase == .verifying)

			actionStrip
		}
		.sheetFrame(.compact)
		/* A container of its own: an identifier on a plain stack is handed down
		 to every control in it and replaces the buttons' own. */
		.accessibilityElement(children: .contain)
		.accessibilityIdentifier(AccessibilityIdentifier.accountRegistrationSheet)
		.onAppear {
			focusedField = model.accountIsEditable ? .account : .email
		}
		.onChange(of: model.focusRequest) { _, field in
			guard let field else { return }
			focusedField = field
			model.didFocus()
		}
	}

	// MARK: - Form

	@ViewBuilder
	private var formSections: some View {
		Section {
			if let error = model.shownGeneralError {
				generalErrorRow(error)
			}

			LabeledContent(.AccountRegistrationSheet.serverLabel) {
				VStack(alignment: .trailing, spacing: 2) {
					Text(model.networkName)
						.textSelection(.enabled)
					if model.isConnected == false {
						Text(.AccountRegistrationSheet.connectsToRegister)
							.font(.callout)
							.foregroundStyle(.secondary)
					}
				}
			}

			accountRow

			LabeledContent {
				TextField(.AccountRegistrationSheet.emailPlaceholder, text: $model.email)
					.labelsHidden()
					.textContentType(.emailAddress)
					.focused($focusedField, equals: .email)
					.accessibilityLabel(.AccountRegistrationSheet.emailLabel)
					.accessibilityIdentifier(AccessibilityIdentifier.accountRegistrationEmail)
			} label: {
				VStack(alignment: .leading, spacing: 2) {
					Text(.AccountRegistrationSheet.emailLabel)
					Text(emailCaption)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			fieldError(.email)
		}

		Section {
			LabeledContent(.AccountRegistrationSheet.passwordLabel) {
				SecureField(.AccountRegistrationSheet.passwordLabel, text: $model.password)
					.labelsHidden()
					.textContentType(.newPassword)
					.focused($focusedField, equals: .password)
					.accessibilityIdentifier(AccessibilityIdentifier.accountRegistrationPassword)
			}
			LabeledContent(.AccountRegistrationSheet.verifyPasswordLabel) {
				SecureField(.AccountRegistrationSheet.verifyPasswordLabel, text: $model.passwordConfirmation)
					.labelsHidden()
					.textContentType(.newPassword)
					.focused($passwordConfirmationIsFocused)
					.accessibilityIdentifier(AccessibilityIdentifier.accountRegistrationPasswordVerify)
					.onSubmit(model.confirm)
			}
			fieldError(.password)
		} header: {
			Text(.AccountRegistrationSheet.passwordSection)
		} footer: {
			passwordFooter
		}
	}

	@ViewBuilder
	private var accountRow: some View {
		if model.accountIsEditable {
			LabeledContent(.AccountRegistrationSheet.accountLabel) {
				TextField(.AccountRegistrationSheet.accountLabel, text: $model.accountName)
					.labelsHidden()
					.textContentType(.username)
					.focused($focusedField, equals: .account)
					.accessibilityIdentifier(AccessibilityIdentifier.accountRegistrationAccount)
			}
			if model.values == nil {
				footnote(Text(.AccountRegistrationSheet.accountUnknownFootnote))
			}
		} else {
			LabeledContent(.AccountRegistrationSheet.accountLabel, value: model.currentNickname)
				.textSelection(.enabled)
				.accessibilityIdentifier(AccessibilityIdentifier.accountRegistrationAccount)
			footnote(Text(.AccountRegistrationSheet.accountFollowsNicknameFootnote))
		}
		fieldError(.account)
	}

	private var emailCaption: LocalizedStringResource {
		switch model.emailRequirement {
		case .required: .AccountRegistrationSheet.emailRequired
		case .optional: .AccountRegistrationSheet.emailOptional
		case .requiredBySomeServers: .AccountRegistrationSheet.emailRequiredBySome
		}
	}

	private var passwordFooter: some View {
		VStack(alignment: .leading, spacing: UISpacing.tight) {
			if let bounds = passwordBounds {
				Text(bounds)
			}
			switch model.transportWarning {
			case .asksFirst:
				Label(.AccountRegistrationSheet.transportAsksFirst, systemImage: "exclamationmark.triangle")
			case .refuses:
				Label(.AccountRegistrationSheet.transportRefuses, systemImage: "exclamationmark.triangle")
			case nil:
				EmptyView()
			}
			if model.replacesSavedPassword {
				Text(.AccountRegistrationSheet.replacesSavedPassword)
			}
		}
		.font(.callout)
		.foregroundStyle(.secondary)
	}

	private var passwordBounds: LocalizedStringResource? {
		switch (model.values?.minimumPasswordBytes, model.values?.maximumPasswordBytes) {
		case let (minimum?, maximum?): .AccountRegistrationSheet.passwordBoundsRange(minimum, maximum)
		case let (minimum?, nil): .AccountRegistrationSheet.passwordBoundsMinimum(minimum)
		case let (nil, maximum?): .AccountRegistrationSheet.passwordBoundsMaximum(maximum)
		case (nil, nil): nil
		}
	}

	// MARK: - Code and result

	private var codeSection: some View {
		Section {
			if model.codeServerMessage.isEmpty == false {
				Text(model.codeServerMessage)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)
			}
			LabeledContent(.AccountRegistrationSheet.codeLabel) {
				TextField(.AccountRegistrationSheet.codeLabel, text: $model.code)
					.labelsHidden()
					.textContentType(.oneTimeCode)
					.focused($focusedField, equals: .code)
					.accessibilityIdentifier(AccessibilityIdentifier.accountRegistrationCode)
					.onSubmit(model.confirm)
			}
			fieldError(.code)
		} footer: {
			footnote(Text(.AccountRegistrationSheet.codeFootnote))
		}
	}

	private func successSection(account: String, credentialsSaved: Bool) -> some View {
		Section {
			Label {
				VStack(alignment: .leading, spacing: UISpacing.tight) {
					Text(.AccountRegistrationSheet.successTitle(account))
						.font(.headline)
					Text(credentialsSaved
						? .AccountRegistrationSheet.successSaved
						: .AccountRegistrationSheet.successNotSaved)
						.foregroundStyle(.secondary)
				}
			} icon: {
				Image(systemName: "checkmark.seal")
					.symbolRenderingMode(.hierarchical)
					.foregroundStyle(.green)
					.imageScale(.large)
			}
			.accessibilityElement(children: .combine)
			.accessibilityIdentifier(AccessibilityIdentifier.accountRegistrationSuccess)
		}
	}

	// MARK: - Pieces

	private func generalErrorRow(_ error: String) -> some View {
		Label {
			VStack(alignment: .leading, spacing: 2) {
				Text(error)
					.foregroundStyle(.primary)
				if let serverMessage = model.generalServerMessage, serverMessage.isEmpty == false {
					Text(serverMessage)
						.font(.callout)
						.foregroundStyle(.secondary)
						.textSelection(.enabled)
				}
			}
		} icon: {
			Image(systemName: "exclamationmark.octagon.fill")
				.foregroundStyle(.red)
		}
		.accessibilityElement(children: .combine)
		.accessibilityIdentifier("account-registration-error")
	}

	@ViewBuilder
	private func fieldError(_ field: AccountRegistrationField) -> some View {
		if let message = model.fieldErrors[field] {
			ValidationMessageLabel(message)
				.accessibilityIdentifier("account-registration-error-\(Self.identifier(for: field))")
		}
	}

	private func footnote(_ text: Text) -> some View {
		text
			.font(.callout)
			.foregroundStyle(.secondary)
			.fixedSize(horizontal: false, vertical: true)
	}

	private static func identifier(for field: AccountRegistrationField) -> String {
		switch field {
		case .account: "account"
		case .email: "email"
		case .password: "password"
		case .code: "code"
		}
	}

	/** The sheet's buttons: Cancel reads Stop while a request is out, the
	 status sits on the leading side, and a finished registration closes with
	 the one button that accepts it. */
	private var actionStrip: some View {
		SheetActions(
			confirmTitle: Text(model.confirmTitle),
			confirmIsDisabled: model.confirmIsDisabled,
			confirmIdentifier: AccessibilityIdentifier.accountRegistrationSubmit,
			cancelTitle: Text(isWaiting ? String(localized: .AccountRegistrationSheet.stopButton) : PromptStrings.Action.cancel),
			cancelIdentifier: "account-registration-cancel",
			confirm: model.confirm,
			cancel: model.phase.isSucceeded ? nil : (isWaiting ? stop : cancel),
			leading: {
				if let status = progressStatus {
					ProgressView()
						.controlSize(.small)
					Text(status)
						.foregroundStyle(.secondary)
						.accessibilityIdentifier("account-registration-status")
				}
			}
		)
	}

	private var isWaiting: Bool {
		model.phase == .submitting || model.phase == .verifying
	}

	private var progressStatus: LocalizedStringResource? {
		switch model.phase {
		case .submitting: .AccountRegistrationSheet.registeringStatus
		case .verifying: .AccountRegistrationSheet.verifyingStatus
		default: nil
		}
	}
}

private extension AccountRegistrationModel.Phase {
	var isSucceeded: Bool {
		if case .succeeded = self {
			return true
		}

		return false
	}
}
