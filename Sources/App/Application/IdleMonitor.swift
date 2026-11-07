// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CoreGraphics

/** Marks the user away after system-wide inactivity, and present again on the
 next input.

 It reads the time since the last input event, which needs no Input Monitoring
 or Accessibility permission, and the login session's active state, so that
 switching to another user counts as away at once. `IdleAwayDecision` decides;
 this owns the clock, the notifications and the ticking task. */
@MainActor
final class IdleMonitor {
	private static let activeInterval = Duration.seconds(15)
	private static let disabledInterval = Duration.seconds(60)

	private let chatSession: @MainActor () -> ChatSession?
	private let idleSeconds: @MainActor () -> TimeInterval
	private let notifications = NotificationSubscriptions()
	private var userSessionIsActive = true
	private var task: Task<Void, Never>?

	init(
		chatSession: @escaping @MainActor () -> ChatSession?,
		idleSeconds: @escaping @MainActor () -> TimeInterval = IdleMonitor.systemIdleSeconds
	) {
		self.chatSession = chatSession
		self.idleSeconds = idleSeconds
	}

	isolated deinit {
		task?.cancel()
		notifications.cancelAll()
	}

	/// Seconds since the last keyboard, mouse or trackpad event.
	static func systemIdleSeconds() -> TimeInterval {
		guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
		return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
	}

	func start() {
		guard task == nil else { return }

		let center = NSWorkspace.shared.notificationCenter
		notifications.observe(NSWorkspace.sessionDidResignActiveNotification, center: center) { [weak self] _ in
			self?.userSessionIsActive = false
			self?.tick()
		}
		notifications.observe(NSWorkspace.sessionDidBecomeActiveNotification, center: center) { [weak self] _ in
			self?.userSessionIsActive = true
			self?.tick()
		}

		task = Task { [weak self] in
			while Task.isCancelled == false {
				let isEnabled = self?.tick() ?? false
				try? await Task.sleep(for: isEnabled ? Self.activeInterval : Self.disabledInterval, tolerance: .seconds(5))
			}
		}
	}

	/// Applies one decision and reports whether idle-away is switched on.
	@discardableResult
	private func tick() -> Bool {
		guard let chatSession = chatSession() else { return false }

		let settings = chatSession.environment.settings
		let decision = IdleAwayDecision.decide(IdleAwayInput(
			idleSeconds: idleSeconds(),
			thresholdSeconds: IdleAwayDecision.thresholdSeconds(minutes: settings.idleAwayMinutes),
			isEnabled: settings.awayOnIdle,
			userSessionIsActive: userSessionIsActive,
			isIdleAway: chatSession.isIdleAway
		))

		switch decision {
		case .none: break
		case .setAway: chatSession.setAutoAwayReason(.idle, holds: true)
		case .clearAway: chatSession.setAutoAwayReason(.idle, holds: false)
		}

		return settings.awayOnIdle
	}
}
