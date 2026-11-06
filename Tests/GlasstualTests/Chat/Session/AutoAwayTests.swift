// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Automatic away")
struct AutoAwayTests {
	// MARK: Ownership

	struct OwnerCase: Sendable {
		let active: Set<AutoAwayReason>
		let owner: AutoAwayReason?
	}

	@Test(
		"The highest-priority reason owns the status",
		arguments: [
			OwnerCase(active: [], owner: nil),
			OwnerCase(active: [.screenSleep], owner: .screenSleep),
			OwnerCase(active: [.idle], owner: .idle),
			OwnerCase(active: [.focus], owner: .focus),
			OwnerCase(active: [.screenSleep, .idle], owner: .idle),
			OwnerCase(active: [.screenSleep, .focus], owner: .focus),
			OwnerCase(active: [.idle, .focus], owner: .focus),
			OwnerCase(active: [.screenSleep, .idle, .focus], owner: .focus),
		]
	)
	func ownership(_ testCase: OwnerCase) {
		#expect(AutoAwayReason.owner(of: testCase.active) == testCase.owner)
	}

	struct MessageCase: Sendable {
		let reason: AutoAwayReason
		let idle: String
		let focus: String?
		let expected: String
	}

	@Test(
		"The owner's own text is used, and the fallback covers empty text",
		arguments: [
			MessageCase(reason: .screenSleep, idle: "idle", focus: "focus", expected: "default"),
			MessageCase(reason: .idle, idle: "gone", focus: "focus", expected: "gone"),
			MessageCase(reason: .idle, idle: "", focus: "focus", expected: "default"),
			MessageCase(reason: .idle, idle: "  \n", focus: nil, expected: "default"),
			MessageCase(reason: .idle, idle: "  gone  ", focus: nil, expected: "gone"),
			MessageCase(reason: .focus, idle: "idle", focus: "heads down", expected: "heads down"),
			MessageCase(reason: .focus, idle: "idle", focus: nil, expected: "default"),
			MessageCase(reason: .focus, idle: "idle", focus: "", expected: "default"),
		]
	)
	func message(_ testCase: MessageCase) {
		#expect(
			AutoAwayReason.message(
				for: testCase.reason,
				idleMessage: testCase.idle,
				focusMessage: testCase.focus,
				fallback: "default"
			) == testCase.expected
		)
	}

	// MARK: Idle decision

	struct DecisionCase: Sendable {
		let idle: TimeInterval
		let isEnabled: Bool
		let isActive: Bool
		let isIdleAway: Bool
		let expected: IdleAwayDecision
	}

	@Test(
		"Idle time against the threshold decides set, clear or nothing",
		arguments: [
			DecisionCase(idle: 0, isEnabled: true, isActive: true, isIdleAway: false, expected: .none),
			DecisionCase(idle: 599, isEnabled: true, isActive: true, isIdleAway: false, expected: .none),
			DecisionCase(idle: 600, isEnabled: true, isActive: true, isIdleAway: false, expected: .setAway),
			DecisionCase(idle: 5000, isEnabled: true, isActive: true, isIdleAway: false, expected: .setAway),
			DecisionCase(idle: 5000, isEnabled: true, isActive: true, isIdleAway: true, expected: .none),
			DecisionCase(idle: 600, isEnabled: true, isActive: true, isIdleAway: true, expected: .none),
			DecisionCase(idle: 599, isEnabled: true, isActive: true, isIdleAway: true, expected: .clearAway),
			DecisionCase(idle: 0, isEnabled: true, isActive: true, isIdleAway: true, expected: .clearAway),
		]
	)
	func thresholdDecision(_ testCase: DecisionCase) {
		#expect(decide(testCase) == testCase.expected)
	}

	@Test(
		"Switching the user away counts as away whatever the idle time",
		arguments: [
			DecisionCase(idle: 0, isEnabled: true, isActive: false, isIdleAway: false, expected: .setAway),
			DecisionCase(idle: 5000, isEnabled: true, isActive: false, isIdleAway: false, expected: .setAway),
			DecisionCase(idle: 0, isEnabled: true, isActive: false, isIdleAway: true, expected: .none),
			DecisionCase(idle: 5000, isEnabled: true, isActive: false, isIdleAway: true, expected: .none),
		]
	)
	func fastUserSwitchDecision(_ testCase: DecisionCase) {
		#expect(decide(testCase) == testCase.expected)
	}

	@Test(
		"A disabled setting never sets away and releases one it set",
		arguments: [
			DecisionCase(idle: 5000, isEnabled: false, isActive: true, isIdleAway: false, expected: .none),
			DecisionCase(idle: 5000, isEnabled: false, isActive: false, isIdleAway: false, expected: .none),
			DecisionCase(idle: 5000, isEnabled: false, isActive: true, isIdleAway: true, expected: .clearAway),
			DecisionCase(idle: 0, isEnabled: false, isActive: false, isIdleAway: true, expected: .clearAway),
		]
	)
	func disabledDecision(_ testCase: DecisionCase) {
		#expect(decide(testCase) == testCase.expected)
	}

	@Test("The threshold is clamped to the supported range")
	func clamping() {
		#expect(IdleAwayDecision.clampedMinutes(0) == 1)
		#expect(IdleAwayDecision.clampedMinutes(-5) == 1)
		#expect(IdleAwayDecision.clampedMinutes(10) == 10)
		#expect(IdleAwayDecision.clampedMinutes(120) == 120)
		#expect(IdleAwayDecision.clampedMinutes(500) == 120)
		#expect(IdleAwayDecision.clampedMinutes(.nan) == 10)
		#expect(IdleAwayDecision.clampedMinutes(.infinity) == 10)
		#expect(IdleAwayDecision.thresholdSeconds(minutes: 2) == 120)
	}

	private func decide(_ testCase: DecisionCase) -> IdleAwayDecision {
		IdleAwayDecision.decide(IdleAwayInput(
			idleSeconds: testCase.idle,
			thresholdSeconds: IdleAwayDecision.thresholdSeconds(minutes: 10),
			isEnabled: testCase.isEnabled,
			userSessionIsActive: testCase.isActive,
			isIdleAway: testCase.isIdleAway
		))
	}
}
