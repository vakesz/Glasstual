// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// How long autojoin waits, and when it gives up waiting.
struct AutojoinPolicyTests {
	@Test("The ceiling is a minute")
	func ceiling() {
		#expect(ServerConfigDefaults.maximumAutojoinConnectCommandDelay == 60)
	}

	@Test("An unattended wait outlasts every warning the user is owed")
	func deadlineCoversTheWarnings() {
		#expect(
			AutojoinPolicy.unattendedAuthenticationDeadline
				== AutojoinPolicy.delayedWarningInterval * TimeInterval(AutojoinPolicy.maximumDelayedWarningCount)
		)
		#expect(AutojoinPolicy.unattendedAuthenticationDeadline == 270)
	}

	struct DelayCase: Sendable {
		let waits: Bool
		let hasCommands: Bool
		let configured: TimeInterval
		let delay: TimeInterval
	}

	nonisolated static let delayCases: [DelayCase] = [
		DelayCase(waits: true, hasCommands: true, configured: 5, delay: 5),
		DelayCase(waits: true, hasCommands: true, configured: 0, delay: 0),
		DelayCase(waits: true, hasCommands: true, configured: -3, delay: 0),
		DelayCase(waits: true, hasCommands: true, configured: 600, delay: 60),
		DelayCase(waits: false, hasCommands: true, configured: 5, delay: 0),
		DelayCase(waits: true, hasCommands: false, configured: 5, delay: 0),
	]

	@Test("The pause after connect commands is clamped and needs both switches", arguments: Self.delayCases)
	func delayAfterConnectCommands(_ testCase: DelayCase) {
		#expect(
			AutojoinPolicy.delayAfterConnectCommands(
				waitsForConnectCommands: testCase.waits,
				hasConnectCommands: testCase.hasCommands,
				configuredDelay: testCase.configured
			) == testCase.delay
		)
	}
}
