// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** The unit tests run inside a full launch of the application. That launch
 used to activate it and raise its windows over the person's work on every
 run; the test host now stays in the background. */
@Suite("Application launch mode")
@MainActor
struct ApplicationLaunchModeTests {
	@Test("A launch without the test-host variable is interactive")
	func launchWithoutVariableIsInteractive() {
		#expect(ApplicationLaunchMode(environment: [:]) == .interactive)
		#expect(ApplicationLaunchMode(environment: [ApplicationLaunchMode.unitTestHostVariable: ""]) == .interactive)
	}

	@Test("The test-host variable makes a background test host")
	func variableMakesTestHost() {
		let mode = ApplicationLaunchMode(environment: [ApplicationLaunchMode.unitTestHostVariable: "1"])

		#expect(mode == .unitTestHost)
	}

	/// Smoke and E2E runs set the review variables and drive the visible
	/// application, so the review variables alone must not hide it.
	@Test("Review isolation alone keeps the interactive launch")
	func reviewIsolationStaysInteractive() {
		let mode = ApplicationLaunchMode(environment: [
			"GLASSTUAL_UI_REVIEW_SUITE": "com.vakesz.glasstual.tests",
			"GLASSTUAL_UI_REVIEW_DIRECTORY": "GlasstualTests",
		])

		#expect(mode == .interactive)
	}

	@Test("An interactive launch comes forward and restores its windows")
	func interactiveLaunchComesForward() {
		let mode = ApplicationLaunchMode.interactive

		#expect(mode.activationPolicy == nil)
		#expect(mode.takesForeground)
		#expect(mode.restoresWindows)
	}

	@Test("The test host cannot activate, raise or restore windows")
	func hostStaysInBackground() {
		let mode = ApplicationLaunchMode.unitTestHost

		#expect(mode.activationPolicy == .prohibited)
		#expect(mode.takesForeground == false)
		#expect(mode.restoresWindows == false)
	}

	/// The scheme's test action is what sets the variable. Without it every
	/// `make test` would take the person's focus again.
	@Test("This test host was launched in the background")
	func currentHostIsBackgroundTestHost() {
		#expect(ApplicationForeground.mode == .unitTestHost)
		#expect(NSApp.activationPolicy() == .prohibited)
		#expect(AppServices.delegate.mainWindow?.isVisible == false)
	}
}
