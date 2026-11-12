// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/** One question in the conversation, drawn with system controls.

 The card is the alert's content laid out above the message field: the title,
 the explanation, a field when the answer needs one, "Don't ask again" when
 the question offers it, and the buttons in the order an alert puts them. It
 is drawn by the application from the registry, never from a line, so nothing
 a server sends can draw one or press its buttons.

 No button has a key equivalent: Return belongs to the message field. A button
 counts only once the card has been still for a moment, so a card that appears
 under the pointer does not catch a click meant for something else, and a
 security question also ignores a click that is part of a double click. */
struct PromptCardView: View {
	@Bindable var prompt: PendingPrompt
	let registry: PendingPromptRegistry
	let answered: (PromptAnswerResult) -> Void

	@State private var isArmed = false
	/// Counts every move of the card on screen. Anything that shifts it — a
	/// card, a note or a banner appearing around it, the window resizing —
	/// makes it wait again before a click counts.
	@State private var placement = 0
	@FocusState private var fieldIsFocused: Bool
	@Environment(\.appearsActive) private var appearsActive

	/// How long a card has to stay where it is before a click counts.
	static let armingDelay = Duration.milliseconds(500)

	private var request: AlertRequest {
		prompt.request
	}

	private var isSecurity: Bool {
		request.sensitivity == .security
	}

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: UISpacing.regular) {
			Image(systemName: symbol)
				.font(.title3)
				.foregroundStyle(isSecurity ? Color.orange : Color.accentColor)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: UISpacing.snug) {
				header
				field
				if request.suppressionKey != nil {
					Toggle(isOn: $prompt.remembers) {
						Text(verbatim: request.suppressionText ?? PromptStrings.Alert.doNotAskAgain)
					}
					.toggleStyle(.checkbox)
					.accessibilityIdentifier(AccessibilityIdentifier.promptRemember(request, number: prompt.number))
				}
				footer
			}
		}
		.padding(UISpacing.wide)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(.regularMaterial, in: .rect(cornerRadius: InputBarLayout.accessoryCornerRadius))
		.overlay {
			RoundedRectangle(cornerRadius: InputBarLayout.accessoryCornerRadius)
				.strokeBorder(isSecurity ? Color.orange.opacity(0.5) : Color(nsColor: .separatorColor))
				.accessibilityHidden(true)
		}
		.accessibilityElement(children: .contain)
		.accessibilityLabel(Text(verbatim: request.title))
		.accessibilityIdentifier(AccessibilityIdentifier.promptCard(request, number: prompt.number))
		.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { _ in
			placement &+= 1
		}
		.task(id: placement) {
			isArmed = false
			try? await Task.sleep(for: Self.armingDelay)
			guard Task.isCancelled == false else { return }
			isArmed = true
		}
		.onChange(of: registry.fieldFocusRequest, initial: true) { _, number in
			if number == prompt.number {
				fieldIsFocused = true
				registry.fieldFocusRequest = nil
			}
		}
	}

	private var symbol: String {
		if isSecurity {
			return "lock.shield"
		}
		return request.isNotice ? "info.circle" : "questionmark.bubble"
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: UISpacing.tight) {
			Text(verbatim: request.title)
				.font(.subheadline.weight(.semibold))
				.fixedSize(horizontal: false, vertical: true)
			if request.body.isEmpty == false {
				Text(verbatim: request.body)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}

	@ViewBuilder
	private var field: some View {
		switch request.field {
		case let .text(placeholder, _, _):
			TextField(text: $prompt.text, prompt: Text(verbatim: placeholder)) {
				Text(verbatim: request.title)
			}
			.textFieldStyle(.roundedBorder)
			.focused($fieldIsFocused)
			.onSubmit(submitField)
			.accessibilityIdentifier(AccessibilityIdentifier.promptField(request, number: prompt.number))
		case let .secure(placeholder):
			SecureField(text: $prompt.text, prompt: Text(verbatim: placeholder)) {
				Text(verbatim: request.title)
			}
			.textFieldStyle(.roundedBorder)
			.focused($fieldIsFocused)
			.onSubmit(submitField)
			.accessibilityIdentifier(AccessibilityIdentifier.promptField(request, number: prompt.number))
		case nil:
			EmptyView()
		}
	}

	private var footer: some View {
		HStack(alignment: .center, spacing: UISpacing.regular) {
			if request.otherButton != nil {
				button(for: .other)
			}
			Text(.InlinePrompts.typeHint(prompt.number, PromptHint.commands(for: request, number: prompt.number).joined(separator: " · ")))
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(2)
				.textSelection(.enabled)
				.accessibilityIdentifier(AccessibilityIdentifier.promptCard(request, number: prompt.number) + "-hint")
			Spacer(minLength: UISpacing.regular)
			if request.alternateButton != nil {
				button(for: .alternate)
			}
			button(for: .default)
		}
		.controlSize(.small)
	}

	@ViewBuilder
	private func button(for response: AlertResponse) -> some View {
		let title = request.title(for: response) ?? ""
		let button = Button(role: request.isDestructive(response) ? .destructive : nil) {
			press(response)
		} label: {
			Text(verbatim: title)
		}
		.disabled(isArmed == false || (response == .default && fieldBlocksSubmit))
		.accessibilityIdentifier(AccessibilityIdentifier.promptButton(request, number: prompt.number, response: response))
		.accessibilityHint(Text(verbatim: request.title))

		if response == request.returnButton, request.isDestructive(response) == false {
			button.buttonStyle(.borderedProminent)
		} else {
			button
		}
	}

	/// A required field needs something in it before the default button counts.
	private var fieldBlocksSubmit: Bool {
		guard let field = request.field, field.isRequired else { return false }
		return prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	/// Return in the field answers as Return does in the alert: with the
	/// default button, and never with one that destroys something.
	private func submitField() {
		guard request.sensitivity == .routine, request.returnButton == .default, fieldBlocksSubmit == false else {
			return
		}
		answered(registry.answer(prompt, with: .default, text: prompt.text, remember: prompt.remembers))
	}

	private func press(_ response: AlertResponse) {
		guard isArmed else { return }
		if isSecurity {
			/* A double click lands twice; the second one is not a decision. */
			guard appearsActive, (NSApp.currentEvent?.clickCount ?? 1) <= 1 else { return }
		}
		answered(registry.answer(prompt, with: response, text: prompt.text, remember: prompt.remembers))
	}
}
