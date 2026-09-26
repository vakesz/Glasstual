// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import os

private let terminationScrollbackSaveTimeout: TimeInterval = 15.0

/** How far shutdown has got.

 One value instead of the five booleans that used to answer for it, each of
 which could disagree with the others: a stage only ever moves forward, and
 every step reads the same value to decide whether its work has already been
 done. */
enum ApplicationTerminationStage: Int, Comparable, Sendable {
	/// Nothing has asked the application to quit.
	case running
	/// The quit confirmation is on screen and its answer decides.
	case confirming
	/// Already submitted Settings saves finish before their editors close.
	case finishingSettings
	/// Sessions are leaving IRC.
	case disconnecting
	/// The transcript files and the history store are being flushed.
	case savingLogs
	/// Accepted credential mutations finish before the application exits.
	case savingCredentials
	/// `NSApp` has been told it may quit.
	case finished

	static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/** The shutdown sequence, and the state only it reads.

 Every route to quitting runs the same three steps, and each one branches on
 `stage` rather than on a flag of its own. The delegate owns one of these and
 forwards AppKit's termination callbacks to it; nothing else is shared, which
 is why the state lives here rather than as stored properties on the delegate
 that nothing else on the delegate touches. */
@MainActor
final class ApplicationTermination {
	private static let logger = Logger(
		subsystem: LogSubsystem.current,
		category: "Termination"
	)

	/// The delegate owns this controller, so the reference back is unowned. It
	/// is how the sequence reaches the window, the sessions and the menus.
	private unowned let delegate: ApplicationDelegate

	private(set) var stage: ApplicationTerminationStage = .running
	/// The two log drains still running. Step three waits for both, or for the
	/// deadline, whichever comes first.
	private var pendingLogDrains = 0
	/// Bounds both scrollback persistence and the independent transcript-file drain.
	private var scrollbackSaveDeadline: SessionTimer?
	private var skipConfirmation = false
	/// The quit confirmation while it is on screen. Cancelling it takes the
	/// sheet down without its answer being acted on.
	private var confirmation: Task<Void, Never>?
	private var settingsTask: Task<Void, Never>?
	private var credentialTask: Task<Void, Never>?

	private var terminatingSessionCount: UInt = 0 {
		didSet {
			if terminatingSessionCount != 0 || isTerminating == false {
				return
			}

			Task { [weak self] in
				self?.terminatingSessionsDidFinish()
			}
		}
	}

	init(delegate: ApplicationDelegate) {
		self.delegate = delegate
	}

	/// Shutdown has begun; accepted Settings saves finish before teardown.
	var isTerminating: Bool {
		stage >= .finishingSettings
	}

	// MARK: - NSApplication Terminate Procedure

	/** The answer is always `.terminateLater`: every route to shutting down
	 runs the three termination steps, and step three is what reports back to
	 NSApp. */
	func applicationShouldTerminate() -> NSApplication.TerminateReply {
		if isTerminating {
			/* Termination is already under way. Answering .terminateNow here
			 used to schedule step one a second time, tearing everything down
			 twice. */
			Self.logger.debug("Termination is already in progress")
		} else if stage == .confirming {
			/* The machine powering off cannot wait for a question the reader may
			 never come back to answer. */
			if skipConfirmation {
				Self.logger.debug("Termination can no longer wait for the confirmation")
				confirmation?.cancel()
				confirmation = nil
				stage = .running
				performStepOne()
			} else {
				Self.logger.debug("Termination confirmation is already on screen")
			}
		} else if skipConfirmation
			|| SettingsKeys.Connection.confirmQuit.value == false
			|| delegate.chatSession.sessions.contains(where: { $0.isConnecting || $0.isConnected }) == false
		{
			performStepOne()
		} else {
			presentConfirmation()
		}

		return .terminateLater
	}

	/** The sheet's answer reports to NSApp and begins termination itself.

	 Sheets stack, so a second ⌘Q while this one is up would queue a second
	 sheet and run both completions: two shutdowns, or a cancel answered on top
	 of one already in flight. The stage is what keeps the second request from
	 asking again.

	 The window comes forward first, because nobody can answer a sheet on a
	 window they cannot see. Quitting from the Dock with the main window closed,
	 or with the application hidden, left termination stuck behind that sheet
	 for good, and a logout stuck behind termination. */
	func presentConfirmation() {
		stage = .confirming

		NSApp.activate()
		delegate.mainWindow.makeKeyAndOrderFront(nil)

		let request = AlertRequest(
			title: PromptStrings.Application.quitTitle,
			body: PromptStrings.Application.quitBody,
			defaultButton: PromptStrings.Application.quitButtonTitle,
			alternateButton: PromptStrings.Action.cancel
		)

		confirmation = Task { [weak self] in
			let outcome = await Alerts.run(request, on: .mainWindow)
			/* A request that could not wait cancelled this task. It took the
			 sheet down and began termination itself. */
			guard Task.isCancelled == false, let self else { return }
			confirmation = nil
			stage = .running

			let result = outcome.response == .default

			Self.logger.debug("Perform termination: \(result)")

			if result == false {
				NSApp.reply(toApplicationShouldTerminate: false)
				return
			}

			performStepOne()
		}
	}

	/** Quit without arguing about it — the machine is powering off.

	 This used to set the terminating flag itself, which made
	 `applicationShouldTerminate` read termination as already under way and
	 answer `.terminateLater` without ever running step one: no session left IRC
	 gracefully and nothing was written to the scrollback. The stage belongs to
	 step one;
	 all this path skips is the confirmation sheet. A sheet already on screen
	 comes down instead of holding termination up. */
	func terminateGracefully() {
		skipConfirmation = true

		NSApp.terminate(nil)
	}

	/// One session has left IRC. Step three runs once the last of them reports in.
	func noteSessionDidFinishTerminating() {
		/* A session that reports in more than once must not trap the subtraction
		 on an unsigned count. */
		guard terminatingSessionCount > 0 else {
			return
		}

		terminatingSessionCount -= 1
	}

	// MARK: - The three steps

	func performStepOne() {
		/* Nothing may run the teardown twice. A second pass re-seeds
		 `terminatingSessionCount` while the first round's sessions are still
		 reporting in. */
		guard isTerminating == false else {
			Self.logger.debug("Step one skipped; termination is already in progress")
			return
		}
		stage = .finishingSettings
		var acceptedSaves = SettingsSaveQueue.shared.waitForSaves()
		settingsTask = Task { [weak self] in
			while true {
				let saved = await acceptedSaves.value
				guard let self else { return }
				guard saved else {
					settingsTask = nil
					stage = .running
					NSApp.reply(toApplicationShouldTerminate: false)
					return
				}
				if SettingsSaveQueue.shared.hasPendingSaves {
					acceptedSaves = SettingsSaveQueue.shared.waitForSaves()
					continue
				}
				settingsTask = nil
				beginTeardown()
				return
			}
		}
	}

	private func beginTeardown() {
		guard stage == .finishingSettings else { return }
		Self.logger.debug("Step one entry")

		stage = .disconnecting
		ServerConnection.cancelPendingRequests()

		AppServices.appearance.prepareForApplicationTermination()

		delegate.mainWindow.prepareForApplicationTermination()

		/* The application keeps its delegate here. Without one, AppKit answers
		 a second quit request, such as another ⌘Q, the Dock's Quit or a
		 logout, with an immediate exit. That exit came before step three saved
		 the chat session and drained the logs.
		 `applicationShouldTerminate` answers the request instead and leaves
		 this shutdown alone. */

		Self.logger.debug("Cancelling lifecycle notification subscriptions")
		delegate.notifications.cancelAll()

		Self.logger.debug("Removing AppleScript event observer")
		NSAppleEventManager.shared().removeEventHandler(
			forEventClass: AEEventClass(kInternetEventClass),
			andEventID: AEEventID(kAEGetURL)
		)

		Self.logger.debug("Stopping the network path monitor")
		delegate.stopWatchingNetworkPath()

		delegate.menuController?.prepareForApplicationTermination()

		performStepTwo()
	}

	private func performStepTwo() {
		guard isTerminating else {
			return
		}

		Self.logger.debug("Step two entry")

		/* We want certain things to 100% happen before the app completely closes.
		 Notable actions: gracefully leaving IRC, flushing the scrollback, etc.
		 Each session decrements -terminatingSessionCount once it has finished and
		 the setter continues with step three once the count reaches zero and the
		 scrollback has been written and transcript files drained. With no sessions,
		 assigning zero here continues immediately. */
		terminatingSessionCount = delegate.chatSession.sessionCount

		delegate.chatSession.prepareForApplicationTermination()
	}

	private func terminatingSessionsDidFinish() {
		guard stage == .disconnecting else {
			return
		}

		stage = .savingLogs
		pendingLogDrains = 2

		Self.logger.debug("All sessions finished; saving history and draining transcript files")

		// Do not await a blocked disk operation in a task group: cancellation cannot
		// interrupt fsync, and the group would still wait for its child to return.
		scrollbackSaveDeadline = SessionTimer.once(after: terminationScrollbackSaveTimeout) { [weak self] in
			guard let self else { return }
			Self.logger.error("Log shutdown deadline expired; pending log data may be lost")
			finishLogDrains()
		}

		FileLogger.prepareForApplicationTermination { [weak self] succeeded in
			guard let self else { return }
			if !succeeded {
				Self.logger.error("Transcript drain completed with file errors; some log data was not saved")
			}
			logDrainDidFinish()
		}

		Scrollback.shared.prepareForApplicationTermination { [weak self] in
			self?.logDrainDidFinish()
		}
	}

	private func logDrainDidFinish() {
		guard stage == .savingLogs, pendingLogDrains > 0 else { return }
		pendingLogDrains -= 1
		guard pendingLogDrains == 0 else { return }
		finishLogDrains()
	}

	/// Runs step three once, whether both drains reported in or the deadline
	/// expired first.
	private func finishLogDrains() {
		guard stage == .savingLogs else { return }
		scrollbackSaveDeadline?.stop()
		scrollbackSaveDeadline = nil
		stage = .savingCredentials
		credentialTask = Task { [weak self] in
			await KeychainPersistence.shared.finishForTermination(confirmRetry: KeychainAlerts.confirmTerminationRetry)
			guard let self else { return }
			credentialTask = nil
			performStepThree()
		}
	}

	private func performStepThree() {
		Self.logger.debug("Step three entry")

		stage = .finished

		Self.logger.debug("Saving the chat session")
		delegate.chatSession.save()

		Self.logger.debug("Saving running internal")
		ApplicationInfo.saveTimeIntervalSinceApplicationInstall()

		Self.logger.debug("Terminate")
		NSApp.reply(toApplicationShouldTerminate: true)
	}
}

extension ApplicationDelegate {
	func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
		termination.applicationShouldTerminate()
	}

	/// Quit without arguing about it — the machine is powering off.
	func terminateGracefully() {
		termination.terminateGracefully()
	}
}

/// The application state the IRC layer branches on, behind a seam so that the
/// connection code does not name the application controller.
extension ApplicationDelegate: ApplicationStatePresenting {
	func noteSessionDidFinishTerminating() {
		termination.noteSessionDidFinishTerminating()
	}
}
