/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Observation
import SwiftUI

public struct InputPromptRequest: Equatable, Sendable {
	public let title: String
	public let message: String
	public let submitButtonTitle: String
	public let cancelButtonTitle: String
	public let initialValue: String

	public init(
		title: String,
		message: String,
		submitButtonTitle: String,
		cancelButtonTitle: String,
		initialValue: String = ""
	) {
		self.title = title
		self.message = message
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

			TextField("", text: $presentation.value)
				.labelsHidden()
				.focused($inputIsFocused)
				.onSubmit(submit)

			HStack {
				Spacer()
				Button(presentation.request.cancelButtonTitle, action: cancel)
					.keyboardShortcut(.cancelAction)
				Button(presentation.request.submitButtonTitle, action: submit)
					.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 380)
		.onAppear {
			inputIsFocused = true
		}
	}
}

public enum InputPrompt {
	@MainActor
	public static func present(
		_ request: InputPromptRequest,
		completion: @escaping @MainActor (InputPromptOutcome) -> Void
	) {
		AppController.shared.mainWindow.presentationModel.presentInputPrompt(
			request,
			completion: completion
		)
	}
}
