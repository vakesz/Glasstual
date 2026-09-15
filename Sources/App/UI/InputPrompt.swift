/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Observation
import SwiftUI

public struct InputPromptRequest: Equatable, Sendable {
	public let title: String
	public let message: String
	/// What the empty field shows: an example of what to type, not a
	/// restatement of the question the message above already asks.
	public let placeholder: String
	public let submitButtonTitle: String
	public let cancelButtonTitle: String
	public let initialValue: String

	public init(
		title: String,
		message: String,
		placeholder: String = "",
		submitButtonTitle: String,
		cancelButtonTitle: String,
		initialValue: String = ""
	) {
		self.title = title
		self.message = message
		self.placeholder = placeholder
		self.submitButtonTitle = submitButtonTitle
		self.cancelButtonTitle = cancelButtonTitle
		self.initialValue = initialValue
	}
}

public enum InputPromptOutcome: Equatable, Sendable {
	case submitted(String)
	case cancelled
}

@MainActor
@Observable
final class InputPromptPresentation: Identifiable {
	let id = UUID()
	let request: InputPromptRequest
	var value: String

	@ObservationIgnored private var completion: (@MainActor (InputPromptOutcome) -> Void)?

	init(
		request: InputPromptRequest,
		completion: @escaping @MainActor (InputPromptOutcome) -> Void
	) {
		self.request = request
		value = request.initialValue
		self.completion = completion
	}

	func finish(_ outcome: InputPromptOutcome) {
		let completion = completion
		self.completion = nil
		completion?(outcome)
	}
}

@MainActor
struct InputPromptView: View {
	@Bindable var presentation: InputPromptPresentation
	@FocusState private var inputIsFocused: Bool

	let submit: () -> Void
	let cancel: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			VStack(alignment: .leading, spacing: 6) {
				Text(verbatim: presentation.request.title)
					.font(.headline)
				Text(verbatim: presentation.request.message)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			TextField(text: $presentation.value, prompt: promptText) { EmptyView() }
				.labelsHidden()
				.focused($inputIsFocused)
				.onSubmit {
					guard hasInput else { return }
					submit()
				}

			HStack {
				Spacer()
				Button(presentation.request.cancelButtonTitle, action: cancel)
					.keyboardShortcut(.cancelAction)
				Button(presentation.request.submitButtonTitle, action: submit)
					.keyboardShortcut(.defaultAction)
					/* Submitting an empty field used to close the prompt and
					 then do nothing, because every caller drops an empty
					 answer. */
					.disabled(hasInput == false)
			}
		}
		.padding(20)
		.frame(width: 380)
		.onAppear {
			inputIsFocused = true
		}
	}

	private var hasInput: Bool {
		presentation.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
	}

	private var promptText: Text? {
		let placeholder = presentation.request.placeholder
		return placeholder.isEmpty ? nil : Text(verbatim: placeholder)
	}
}

public enum InputPrompt {
	/// Asks on the window installed as ``SheetPresentation/host``. Before one
	/// exists there is nowhere to ask, and the prompt answers as cancelled.
	@MainActor
	public static func present(
		_ request: InputPromptRequest,
		completion: @escaping @MainActor (InputPromptOutcome) -> Void
	) {
		guard let host = SheetPresentation.host else {
			completion(.cancelled)
			return
		}
		host.presentInputPrompt(request, completion: completion)
	}
}
