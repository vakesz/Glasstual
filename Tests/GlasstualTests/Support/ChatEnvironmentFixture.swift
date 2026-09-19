// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual

/// A menu bar that records the sheets it was asked to raise.
@MainActor
final class RecordingMenuPresenter: MenuPresenting {
	private(set) var soundsMuted: Bool?
	private(set) var serverPropertiesSelections: [ServerPropertiesDestination] = []
	private(set) var nicknameColorSheets: [String] = []
	private(set) var revealedFolders: [URL] = []

	func toggleMuteOnNotificationSoundsShortcut(on muted: Bool) {
		soundsMuted = muted
	}

	func showServerPropertiesSheet(for _: ServerSession, selection: ServerPropertiesDestination) {
		serverPropertiesSelections.append(selection)
	}

	func showNicknameColorSheet(forNickname nickname: String) {
		nicknameColorSheets.append(nickname)
	}

	func openAcknowledgements(_: Any?) {}

	func navigate(to _: URL) {}

	func revealInFinder(_ url: URL) {
		revealedFolders.append(url)
	}
}

/// A notification centre that records what the connection asked it to post
/// instead of asking the system for permission to post anything.
@MainActor
final class RecordingNotificationPresenter: UserNotificationPresenting {
	var areNotificationsDisabled = false
	/// Whether the next claim in a thread alerts. The burst policy itself is
	/// ``UserNotificationController``'s; a test drives the answer.
	var claimsAlert = true

	private(set) var posted: [PendingUserNotification] = []
	private(set) var claimedThreads: [String?] = []
	private(set) var attentionRequests = 0
	private(set) var playedSounds: [String] = []

	func claimsAlert(inThread thread: String?) -> Bool {
		claimedThreads.append(thread)

		return claimsAlert
	}

	func post(_ notification: PendingUserNotification) {
		posted.append(notification)
	}

	func requestUserAttention() {
		attentionRequests += 1
	}

	func playAlertSound(named name: String) {
		playedSounds.append(name)
	}
}

/// An application that is never terminating and never in ghost mode.
@MainActor
final class RecordingApplicationState: ApplicationStatePresenting {
	var ghostModeIsOn = false
	var applicationIsTerminating = false
	private(set) var sessionsFinishedTerminating = 0

	func noteSessionDidFinishTerminating() {
		sessionsFinishedTerminating += 1
	}
}

/** Owns the doubles a test session talks to. `ChatServices` holds them weakly,
 so something has to keep them alive for as long as the session does. */
@MainActor
final class ChatEnvironmentFixture {
	let output = RecordingSessionOutput()
	let menu = RecordingMenuPresenter()
	let applicationState = RecordingApplicationState()
	let notifications = RecordingNotificationPresenter()
	/// A chat session of this fixture's own, so channel creation works without the
	/// application's. `ChatServices` refers to it weakly; this keeps it alive.
	let chatSession: ChatSession
	private(set) var environment: ChatEnvironment

	init(settings: ChatSettings = .current()) {
		let services = ChatServices(
			output: output,
			menu: menu,
			applicationState: applicationState,
			notifications: notifications
		)
		environment = ChatEnvironment(settings: settings, services: services)
		/* The directory installs itself in the services it is given. */
		chatSession = ChatSession(environment: environment)
	}

	/// Re-reads the defaults store, for a test that writes a setting after
	/// the session already exists.
	func refreshSettings() {
		environment.settings = .current()
	}
}
