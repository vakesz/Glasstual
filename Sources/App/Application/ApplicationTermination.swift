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
	/// Clients are leaving IRC.
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

extension ApplicationDelegate {
	// MARK: - NSApplication Terminate Procedure

	/** The answer is always `.terminateLater`: every route to shutting down
	 runs the three termination steps, and step three is what reports back to
	 NSApp. */
	func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
		if applicationIsTerminating {
			/* Termination is already under way. Answering .terminateNow here
			 used to schedule step one a second time, tearing everything down
			 twice. */
			Self.terminationLogger.debug("Termination is already in progress")
		} else if terminationStage == .confirming {
			/* The machine powering off cannot wait for a question the reader may
			 never come back to answer. */
			if skipTerminateConfirmation {
				Self.terminationLogger.debug("Termination can no longer wait for the confirmation")
				terminationConfirmation?.cancel()
				terminationConfirmation = nil
				terminationStage = .running
				performApplicationTerminationStepOne()
			} else {
				Self.terminationLogger.debug("Termination confirmation is already on screen")
			}
		} else if skipTerminateConfirmation
			|| Preferences.Connection.confirmQuit.value == false
			|| clientDirectory.clientList.contains(where: { $0.isConnecting || $0.isConnected }) == false
		{
			performApplicationTerminationStepOne()
		} else {
			presentTerminationConfirmation()
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
	func presentTerminationConfirmation() {
		terminationStage = .confirming

		NSApp.activate()
		mainWindow.makeKeyAndOrderFront(nil)

		let request = AlertRequest(
			title: PromptStrings.Application.quitTitle,
			body: PromptStrings.Application.quitBody,
			defaultButton: PromptStrings.Application.quitButtonTitle,
			alternateButton: PromptStrings.Action.cancel
		)

		terminationConfirmation = Task { [weak self] in
			let outcome = await Alerts.run(request, on: .mainWindow)
			/* A request that could not wait cancelled this task. It took the
			 sheet down and began termination itself. */
			guard Task.isCancelled == false, let self else { return }
			terminationConfirmation = nil
			terminationStage = .running

			let result = outcome.response == .default

			Self.terminationLogger.debug("Perform termination: \(result)")

			if result == false {
				NSApp.reply(toApplicationShouldTerminate: false)
				return
			}

			performApplicationTerminationStepOne()
		}
	}

	func terminatingClientsDidFinish() {
		guard terminationStage == .disconnecting else {
			return
		}

		terminationStage = .savingLogs
		pendingLogDrains = 2

		Self.terminationLogger.debug("All clients finished; saving history and draining transcript files")

		// Do not await a blocked disk operation in a task group: cancellation cannot
		// interrupt fsync, and the group would still wait for its child to return.
		scrollbackSaveDeadline = ClientTimer.once(after: terminationScrollbackSaveTimeout) { [weak self] in
			guard let self else { return }
			Self.terminationLogger.error("Log shutdown deadline expired; pending log data may be lost")
			finishTermination()
		}

		FileLogger.prepareForApplicationTermination { [weak self] succeeded in
			guard let self else { return }
			if !succeeded {
				Self.terminationLogger.error("Transcript drain completed with file errors; some log data was not saved")
			}
			logDrainDidFinish()
		}

		Scrollback.shared
			.prepareForApplicationTermination { [weak self] in
				Task { @MainActor in
					self?.logDrainDidFinish()
				}
			}
	}

	private func logDrainDidFinish() {
		guard terminationStage == .savingLogs, pendingLogDrains > 0 else { return }
		pendingLogDrains -= 1
		guard pendingLogDrains == 0 else { return }
		finishTermination()
	}

	/// Runs step three once, whether both drains reported in or the deadline
	/// expired first.
	private func finishTermination() {
		guard terminationStage == .savingLogs else { return }
		scrollbackSaveDeadline?.stop()
		scrollbackSaveDeadline = nil
		terminationStage = .savingCredentials
		credentialTerminationTask = Task { [weak self] in
			await KeychainPersistence.shared.finishForTermination(confirmRetry: KeychainAlerts.confirmTerminationRetry)
			guard let self else { return }
			credentialTerminationTask = nil
			performApplicationTerminationStepThree()
		}
	}

	func performApplicationTerminationStepOne() {
		/* Nothing may run the teardown twice. A second pass re-seeds
		 `terminatingClientCount` while the first round's clients are still
		 reporting in. */
		guard applicationIsTerminating == false else {
			Self.terminationLogger.debug("Step one skipped; termination is already in progress")
			return
		}
		terminationStage = .finishingSettings
		var acceptedSaves = KeychainPersistence.shared.waitForSettingsSaves()
		settingsTerminationTask = Task { [weak self] in
			while true {
				let saved = await acceptedSaves.value
				guard let self else { return }
				guard saved else {
					settingsTerminationTask = nil
					terminationStage = .running
					NSApp.reply(toApplicationShouldTerminate: false)
					return
				}
				if KeychainPersistence.shared.hasPendingSettingsSaves {
					acceptedSaves = KeychainPersistence.shared.waitForSettingsSaves()
					continue
				}
				settingsTerminationTask = nil
				beginApplicationTeardown()
				return
			}
		}
	}

	private func beginApplicationTeardown() {
		guard terminationStage == .finishingSettings else { return }
		Self.terminationLogger.debug("Step one entry")

		terminationStage = .disconnecting
		ServerConnectionController.cancelPendingRequests()

		AppServices.appearance.prepareForApplicationTermination()

		mainWindow.prepareForApplicationTermination()

		/* The application keeps its delegate here. Without one, AppKit answers
		 a second quit request, such as another ⌘Q, the Dock's Quit or a
		 logout, with an immediate exit. That exit came before step three saved
		 the client directory and drained the logs.
		 `applicationShouldTerminate` answers the request instead and leaves
		 this shutdown alone. */

		Self.terminationLogger.debug("Cancelling lifecycle notification subscriptions")
		notifications.cancelAll()

		Self.terminationLogger.debug("Removing AppleScript event observer")
		NSAppleEventManager.shared().removeEventHandler(
			forEventClass: AEEventClass(kInternetEventClass),
			andEventID: AEEventID(kAEGetURL)
		)

		Self.terminationLogger.debug("Stopping the network path monitor")
		stopWatchingNetworkPath()

		menuController?.prepareForApplicationTermination()

		performApplicationTerminationStepTwo()
	}

	private func performApplicationTerminationStepTwo() {
		guard applicationIsTerminating else {
			return
		}

		Self.terminationLogger.debug("Step two entry")

		/* We want certain things to 100% happen before the app completely closes.
		 Notable actions: gracefully leaving IRC, saving historic logs, etc.
		 Each client decrements -terminatingClientCount once it has finished and
		 the setter continues with step three once the count reaches zero and the
		 historic log has been saved and transcript files drained. With no clients,
		 assigning zero here continues immediately. */
		terminatingClientCount = clientDirectory.clientCount

		clientDirectory.prepareForApplicationTermination()
	}

	private func performApplicationTerminationStepThree() {
		Self.terminationLogger.debug("Step three entry")

		terminationStage = .finished

		Self.terminationLogger.debug("Saving the client directory")
		clientDirectory.save()

		Self.terminationLogger.debug("Saving running internal")
		ApplicationInfo.saveTimeIntervalSinceApplicationInstall()

		Self.terminationLogger.debug("Terminate")
		NSApp.reply(toApplicationShouldTerminate: true)
	}

	/** Quit without arguing about it — the machine is powering off.

	 This used to set `applicationIsTerminating` itself, which made
	 `applicationShouldTerminate` read termination as already under way and
	 answer `.terminateLater` without ever running step one: no client left IRC
	 gracefully and no historic log was saved. The flag belongs to step one;
	 all this path skips is the confirmation sheet. A sheet already on screen
	 comes down instead of holding termination up. */
	func terminateGracefully() {
		skipTerminateConfirmation = true

		NSApp.terminate(nil)
	}
}

/// The application state the IRC layer branches on, behind a seam so that the
/// connection code does not name the application controller.
extension ApplicationDelegate: ClientApplicationState {
	func noteClientDidFinishTerminating() {
		/* A client that reports in more than once must not trap the subtraction
		 on an unsigned count. */
		guard terminatingClientCount > 0 else {
			return
		}

		terminatingClientCount -= 1
	}
}
