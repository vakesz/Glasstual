// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Answers every alert with one scripted button and records what it was shown.
@MainActor
private final class ScriptedLinkPresenter: AlertPresenter {
	private(set) var requests: [AlertRequest] = []
	let response: AlertResponse

	init(answering response: AlertResponse) {
		self.response = response
	}

	func present(_ request: AlertRequest, in _: AlertPresentation) async -> AlertPresenterResult {
		requests.append(request)
		return AlertPresenterResult(response: response, suppressionChecked: false)
	}
}

/// What the handler performed, in order.
@MainActor
private final class PerformedActions {
	private(set) var actions: [ApplicationLink.Action] = []

	func record(_ action: ApplicationLink.Action, _: URL) {
		actions.append(action)
	}
}

/** A `glasstual:` link that reveals something on disk or connects to a server
 is asked about wherever it comes from: another application, a web page, a
 file, or a transcript whose link `NSWorkspace` hands back. */
@MainActor
@Suite("Application link handler")
struct ApplicationLinkHandlerTests {
	@Test("A support-channel link that is cancelled does nothing")
	func cancelledLinkDoesNotPerform() async throws {
		let presenter = ScriptedLinkPresenter(answering: .default)
		let performed = PerformedActions()

		let confirmation = ApplicationLinkHandler.open(
			"glasstual://support-channel", presenter: presenter, perform: performed.record
		)
		await confirmation?.value

		let request = try #require(presenter.requests.first)
		#expect(confirmation != nil)
		#expect(presenter.requests.count == 1)
		#expect(request.body == "glasstual://support-channel")
		#expect(request.suppressionKey == nil)
		#expect(request.defaultButton == PromptStrings.Action.cancel)
		#expect(performed.actions.isEmpty)
	}

	@Test("A support-channel link that is confirmed connects once")
	func confirmedLinkPerformsOnce() async {
		let presenter = ScriptedLinkPresenter(answering: .alternate)
		let performed = PerformedActions()

		await ApplicationLinkHandler.open(
			"glasstual://support-channel", presenter: presenter, perform: performed.record
		)?.value

		#expect(presenter.requests.count == 1)
		#expect(performed.actions == [.supportChannel])
	}

	@Test("Every link that reveals a folder or connects is asked about", arguments: [
		"glasstual://application-support-folder", "glasstual://custom-scripts-folder",
		"glasstual://diagnostic-reports-folder", "glasstual://testing-channel",
	])
	func everyConfirmedActionAsks(link: String) async {
		let presenter = ScriptedLinkPresenter(answering: .default)
		let performed = PerformedActions()

		await ApplicationLinkHandler.open(link, presenter: presenter, perform: performed.record)?.value

		#expect(presenter.requests.map(\.body) == [link])
		#expect(performed.actions.isEmpty)
	}

	/// Spotlight results and Shortcuts open conversations through `goto`, which
	/// changes nothing but the selection.
	@Test("A goto link is followed without asking")
	func gotoIsNotConfirmed() {
		let presenter = ScriptedLinkPresenter(answering: .default)
		let performed = PerformedActions()

		let confirmation = ApplicationLinkHandler.open(
			"glasstual://goto/conversation", presenter: presenter, perform: performed.record
		)

		#expect(confirmation == nil)
		#expect(presenter.requests.isEmpty)
		#expect(performed.actions == [.goto])
	}

	@Test("A burst of links from elsewhere asks once, about the last of them")
	func burstAsksOnce() async {
		let presenter = ScriptedLinkPresenter(answering: .alternate)
		let performed = PerformedActions()

		let first = ApplicationLinkHandler.open(
			"glasstual://support-channel", presenter: presenter, perform: performed.record
		)
		let second = ApplicationLinkHandler.open(
			"glasstual://testing-channel", presenter: presenter, perform: performed.record
		)
		await first?.value
		await second?.value

		#expect(presenter.requests.map(\.body) == ["glasstual://testing-channel"])
		#expect(performed.actions == [.testingChannel])
	}
}
