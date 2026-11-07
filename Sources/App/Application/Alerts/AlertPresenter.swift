// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import SwiftUI

/// The presentation half of showing an alert: put it on screen, run it, report
/// the button and whether the suppression checkbox ended up ticked. Injected so
/// `Alerts`'s suppression policy is testable on its own.
@MainActor
protocol AlertPresenter {
	func present(_ request: AlertRequest, in presentation: AlertPresentation) async -> AlertPresenterResult
}

nonisolated struct AlertPresenterResult: Equatable, Sendable {
	let response: AlertResponse
	let suppressionChecked: Bool
}
