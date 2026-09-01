/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/// Records what it was asked to show and answers with a scripted response, so
/// the suppression policy around presentation can be exercised without a
/// window server.
@MainActor
private final class RecordingAlertPresenter: AlertPresenter {
	private(set) var requests: [AlertRequest] = []
	private(set) var presentations: [String] = []
	var result: AlertPresenterResult

	init(response: AlertResponse = .default, suppressionChecked: Bool = false) {
		result = AlertPresenterResult(response: response, suppressionChecked: suppressionChecked)
	}

	func present(_ request: AlertRequest, in presentation: AlertPresentation) async -> AlertPresenterResult {
		requests.append(request)
		switch presentation {
		case .applicationModal: presentations.append("modal")
		case .mainWindow: presentations.append("mainWindow")
		case .anyVisibleWindow: presentations.append("anyVisibleWindow")
		}
		return result
	}

	func presentModal(_ request: AlertRequest) -> AlertPresenterResult {
		requests.append(request)
		presentations.append("runModal")
		return result
	}
}

@Suite("Alert requests")
@MainActor
struct AlertRequestTests {
	/// Every test uses its own key, because a suppressed key is written to the
	/// scratch defaults suite the scheme points the tests at.
	private static func uniqueKey() -> String {
		"AlertRequestTests \(UUID().uuidString)"
	}

	@Test("A request without a suppression key is presented as written")
	func plainRequestIsPresented() async {
		let presenter = RecordingAlertPresenter(response: .alternate)
		let request = AlertRequest(
			title: "Title",
			body: "Body",
			defaultButton: "OK",
			alternateButton: "Cancel"
		)

		let outcome = await Alerts.run(request, on: .anyVisibleWindow, using: presenter)

		#expect(outcome == AlertOutcome(response: .alternate, isSuppressed: false))
		#expect(presenter.requests.count == 1)
		#expect(presenter.requests.first?.title == "Title")
		#expect(presenter.requests.first?.suppressionKey == nil)
		#expect(presenter.presentations == ["anyVisibleWindow"])
	}

	@Test("The presentation the caller asked for is the one used")
	func presentationIsForwarded() async {
		let presenter = RecordingAlertPresenter()
		let request = AlertRequest(title: "Title", body: "Body", defaultButton: "OK")
		await Alerts.run(request, on: .mainWindow, using: presenter)
		await Alerts.run(request, on: .applicationModal, using: presenter)
		Alerts.runModal(request, using: presenter)

		#expect(presenter.presentations == ["mainWindow", "modal", "runModal"])
	}

	@Test("A suppression key is prefixed and given default checkbox text")
	func suppressionKeyIsResolved() async {
		let presenter = RecordingAlertPresenter()
		let baseKey = Self.uniqueKey()
		let request = AlertRequest(
			title: "Title",
			body: "Body",
			defaultButton: "OK",
			suppressionKey: baseKey
		)

		await Alerts.run(request, on: .anyVisibleWindow, using: presenter)

		let presented = presenter.requests.first
		#expect(presented?.suppressionKey == Alerts.suppressionKey(withBase: baseKey))
		#expect(presented?.suppressionKey != baseKey)
		#expect(presented?.suppressionText?.isEmpty == false)
	}

	@Test("An already-prefixed suppression key is not prefixed twice")
	func suppressionKeyIsNotDoublePrefixed() {
		let baseKey = Self.uniqueKey()
		let resolved = Alerts.suppressionKey(withBase: baseKey)
		#expect(Alerts.suppressionKey(withBase: resolved) == resolved)
	}

	@Test("Ticking the checkbox records the choice, and the next run is skipped")
	func suppressionIsRecordedAndHonoured() async {
		let baseKey = Self.uniqueKey()
		let request = AlertRequest(
			title: "Title",
			body: "Body",
			defaultButton: "OK",
			alternateButton: "Cancel",
			suppressionKey: baseKey
		)

		let first = RecordingAlertPresenter(response: .alternate, suppressionChecked: true)
		let firstOutcome = await Alerts.run(request, on: .anyVisibleWindow, using: first)

		#expect(firstOutcome == AlertOutcome(response: .alternate, isSuppressed: true))
		#expect(first.requests.count == 1)
		#expect(Alerts.isSuppressed(baseKey: baseKey))

		let second = RecordingAlertPresenter(response: .other)
		let secondOutcome = await Alerts.run(request, on: .anyVisibleWindow, using: second)

		#expect(second.requests.isEmpty, "A suppressed alert must not reach the presenter")
		#expect(secondOutcome == AlertOutcome(response: .default, isSuppressed: true))
	}

	@Test("Leaving the checkbox alone records nothing")
	func unsuppressedAlertRecordsNothing() async {
		let baseKey = Self.uniqueKey()
		let request = AlertRequest(
			title: "Title",
			body: "Body",
			defaultButton: "OK",
			suppressionKey: baseKey
		)

		let presenter = RecordingAlertPresenter(suppressionChecked: false)
		let outcome = await Alerts.run(request, on: .anyVisibleWindow, using: presenter)

		#expect(outcome.isSuppressed == false)
		#expect(Alerts.isSuppressed(baseKey: baseKey) == false)
	}

	@Test("The blocking form applies the same suppression policy")
	func modalRunHonoursSuppression() {
		let baseKey = Self.uniqueKey()
		let request = AlertRequest(
			title: "Title",
			body: "Body",
			defaultButton: "OK",
			suppressionKey: baseKey
		)

		let first = RecordingAlertPresenter(response: .default, suppressionChecked: true)
		_ = Alerts.runModal(request, using: first)
		#expect(first.requests.count == 1)

		let second = RecordingAlertPresenter(response: .alternate)
		let outcome = Alerts.runModal(request, using: second)

		#expect(second.requests.isEmpty)
		#expect(outcome == AlertOutcome(response: .default, isSuppressed: true))
	}

	/// The suppression checkbox is only offered when a key can record the
	/// answer; the request carries the key, so the presenter can tell.
	@Test("A request without a key carries no checkbox text")
	func noKeyMeansNoCheckbox() async {
		let presenter = RecordingAlertPresenter()
		let request = AlertRequest(title: "Title", body: "Body", defaultButton: "OK")

		await Alerts.run(request, on: .anyVisibleWindow, using: presenter)

		#expect(presenter.requests.first?.suppressionKey == nil)
		#expect(presenter.requests.first?.suppressionText == nil)
	}

	@Test("Caller-supplied checkbox text is kept")
	func explicitSuppressionTextIsKept() async {
		let presenter = RecordingAlertPresenter()
		let request = AlertRequest(
			title: "Title",
			body: "Body",
			defaultButton: "OK",
			suppressionKey: Self.uniqueKey(),
			suppressionText: "Never mention this again"
		)

		await Alerts.run(request, on: .anyVisibleWindow, using: presenter)

		#expect(presenter.requests.first?.suppressionText == "Never mention this again")
	}
}
