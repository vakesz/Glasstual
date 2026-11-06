// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Why the application marked the user away without being asked.

 The cases are ordered by priority: when several hold at once, the greatest
 one owns the status and supplies its message. An away the user set by hand is
 not a reason and is never overridden. */
nonisolated enum AutoAwayReason: Int, CaseIterable, Comparable, Sendable {
	case screenSleep
	case idle
	case focus

	static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.rawValue < rhs.rawValue
	}

	/// The reason that owns the status while every one of `active` holds.
	static func owner(of active: Set<Self>) -> Self? {
		active.max()
	}

	/** The comment the away carries: the owner's own text when it has one,
	 `fallback` otherwise. Whitespace alone counts as no text. */
	static func message(
		for reason: Self,
		idleMessage: String,
		focusMessage: String?,
		fallback: String
	) -> String {
		let candidate = switch reason {
		case .screenSleep: ""
		case .idle: idleMessage
		case .focus: focusMessage ?? ""
		}
		let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? fallback : trimmed
	}
}

/// What the idle monitor reads on each tick.
nonisolated struct IdleAwayInput: Equatable, Sendable {
	/// Seconds since the last keyboard, mouse or trackpad event of this login session.
	var idleSeconds: TimeInterval
	var thresholdSeconds: TimeInterval
	var isEnabled: Bool
	/// Whether this login session is the one on screen, rather than switched away from.
	var userSessionIsActive: Bool
	/// Whether the idle reason currently holds.
	var isIdleAway: Bool
}

/** What to do about idle-away on one tick. A pure function of `IdleAwayInput`,
 so the thresholds and the fast-user-switch rule are testable without a clock. */
nonisolated enum IdleAwayDecision: Equatable, Sendable {
	case none
	case setAway
	case clearAway

	static let minimumMinutes = 1.0
	static let maximumMinutes = 120.0
	static let defaultMinutes = 10.0

	/// The stored minutes, forced into the supported range. Not a number reads as the default.
	static func clampedMinutes(_ minutes: Double) -> Double {
		guard minutes.isFinite else { return defaultMinutes }
		return min(max(minutes, minimumMinutes), maximumMinutes)
	}

	static func thresholdSeconds(minutes: Double) -> TimeInterval {
		clampedMinutes(minutes) * 60
	}

	static func decide(_ input: IdleAwayInput) -> Self {
		guard input.isEnabled else {
			return input.isIdleAway ? .clearAway : .none
		}

		if input.userSessionIsActive == false {
			return input.isIdleAway ? .none : .setAway
		}

		let isIdle = input.idleSeconds >= input.thresholdSeconds
		switch (input.isIdleAway, isIdle) {
		case (false, true): return .setAway
		case (true, false): return .clearAway
		default: return .none
		}
	}
}
