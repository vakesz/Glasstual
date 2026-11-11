// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// Signs a registered connection in to services again with SASL, without
/// reconnecting. The default button signs in, and becomes Done once the
/// exchange has ended.
@MainActor
final class SASLSignInSheet: SheetSession, SessionScoped {
	private(set) var sessionId: String?
	let model: SASLSignInModel

	init(session: ServerSession) {
		sessionId = session.uniqueIdentifier
		model = SASLSignInModel(session: session)
		super.init(window: nil)
		setContent(SASLSignInView(
			model: model,
			submit: { [weak self] in self?.submit() },
			cancel: { [weak self] in self?.cancel() }
		))
	}

	override func submit() {
		guard model.isFinished else {
			model.signIn()
			return
		}
		super.submit()
	}
}

@MainActor
struct SASLSignInView: View {
	@Bindable var model: SASLSignInModel

	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var pickerIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			SheetHeading(.AccountSignIn.title, subtitle: Text(.AccountSignIn.subtitle))

			Form {
				Section {
					LabeledContent(.AccountSignIn.account) {
						if let account = model.account {
							Text(verbatim: account)
								.textSelection(.enabled)
						} else {
							Text(.AccountSignIn.notSignedIn)
								.foregroundStyle(.secondary)
						}
					}

					Picker(.AccountSignIn.mechanism, selection: $model.selection) {
						Text(.AccountSignIn.automatic)
							.tag(SASLMechanismChoice.automatic)
						Divider()
						ForEach(model.options) { option in
							Text(verbatim: "\(option.mechanism.localizedTitle) — \(option.mechanism.wireName)")
								.tag(SASLMechanismChoice.mechanism(option.mechanism))
								.disabled(option.unavailableReason != nil)
								.help(option.unavailableReason ?? "")
						}
					}
					.pickerStyle(.menu)
					.focused($pickerIsFocused)
					.disabled(model.state == .inProgress)
					.accessibilityIdentifier("sasl-sign-in-mechanism")

					if case let .mechanism(mechanism) = model.selection,
					   let reason = model.options.first(where: { $0.mechanism == mechanism })?.unavailableReason
					{
						Text(verbatim: reason)
							.font(.callout)
							.foregroundStyle(.secondary)
					}
				}

				resultSection
			}
			.formStyle(.grouped)

			SheetActions(
				confirmTitle: Text(model.isFinished ? .AccountSignIn.done : .AccountSignIn.signIn),
				confirmIsDisabled: model.isFinished == false && model.canSignIn == false,
				confirm: submit,
				cancel: cancel
			)
		}
		.frame(minWidth: 420, idealWidth: 460, maxWidth: .infinity)
		.onAppear {
			pickerIsFocused = true
		}
	}

	@ViewBuilder private var resultSection: some View {
		switch model.state {
		case .ready:
			EmptyView()
		case .inProgress:
			Section {
				HStack(spacing: 8) {
					ProgressView()
						.controlSize(.small)
					Text(.AccountSignIn.inProgress)
				}
				.accessibilityElement(children: .combine)
			}
		case let .succeeded(text):
			Section {
				Label {
					Text(verbatim: text)
				} icon: {
					Image(systemName: "checkmark.circle.fill")
						.foregroundStyle(.green)
				}
				.accessibilityIdentifier("sasl-sign-in-result")
			}
		case let .failed(text):
			Section {
				Label {
					Text(verbatim: text)
				} icon: {
					Image(systemName: "exclamationmark.triangle.fill")
						.foregroundStyle(.yellow)
				}
				.accessibilityIdentifier("sasl-sign-in-result")
			}
		}
	}
}
