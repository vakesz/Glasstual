// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

enum ApplicationSceneID {
	static let about = "about"
	static let channelMaskList = "channel-ban-list"
	static let channelSpotlight = "channel-spotlight"
	static let fileTransfers = "file-transfers"
	static let onboarding = "onboarding"
	static let serverChannelList = "server-channel-list"
	static let highlightLog = "highlight-log"
}

/** Stable identity for a window group that presents one logical window.

 `Window` scenes currently fail to open through an AppKit-hosted scene
 representation. A value-keyed group keeps the working presentation path
 without allowing repeated commands to create duplicate windows. */
enum SingletonSceneValue: String, Codable, Hashable {
	case instance
}

/** What one keyed scene has open, one session per window.

 Every such scene wants the same three things: the session a window already has,
 a new one where there is none, and the session back when the window goes so the
 caller can close it. Each of them used to spell all three out. The feature whose
 windows these are owns the box; a feature with a single window keeps that
 session itself. */
struct SceneSessions<Key: Hashable, Session> {
	private var sessions: [Key: Session] = [:]

	/// The session `key` has open, or nil when no window is showing one.
	subscript(key: Key) -> Session? {
		sessions[key]
	}

	/// The session `key` already has, or a new one put in its place.
	mutating func open(_ key: Key, making make: () -> Session) -> Session {
		if let existing = sessions[key] {
			return existing
		}

		let created = make()
		sessions[key] = created

		return created
	}

	/// Forgets `key`'s session and hands it back, so the caller can close it.
	@discardableResult
	mutating func close(_ key: Key) -> Session? {
		sessions.removeValue(forKey: key)
	}
}

/** Every scene the application declares.

 Each feature's scene is handed the window sessions that feature owns, so the
 shell installs and opens windows without knowing what any of them is showing. */
private struct ApplicationSceneGraph: Scene {
	let settingsRequest: SettingsSceneRequest

	var body: some Scene {
		AboutScene()
		ChannelMaskListScene(window: AppServices.channelMaskList)
		ChannelSpotlightScene(window: AppServices.channelSpotlight)
		FileTransferListScene(center: AppServices.fileTransfers)
		OnboardingScene()
		ServerChannelListScene(windows: AppServices.serverChannelLists)
		HighlightLogScene(windows: AppServices.highlightLogs)
		SettingsScene(request: settingsRequest)
	}
}

/** Installs SwiftUI scenes while the process lifecycle is still hosted by the
 existing application delegate, and opens and dismisses them by scene id.

 Scene registration is the migration seam: each window can move to SwiftUI
 without creating a second application root. What a window is showing belongs to
 the feature that owns its session, which is why nothing here names one. */
@MainActor
final class ApplicationScenes {
	private let settingsRequest = SettingsSceneRequest()

	/** One represented scene graph keeps registration and presentation in one
	 environment instead of building the same AppKit bridge for every feature. */
	private lazy var representation: NSHostingSceneRepresentation<ApplicationSceneGraph> =
		.init { [settingsRequest] in
			ApplicationSceneGraph(settingsRequest: settingsRequest)
		}

	private var isInstalled = false

	func install(in application: NSApplication) {
		guard isInstalled == false else { return }
		isInstalled = true
		application.addSceneRepresentation(representation)
	}

	func open(_ sceneID: String) {
		representation.environment.openWindow(id: sceneID)
	}

	/// Opens the window a keyed scene shows for `value`, or brings that window
	/// forward when it is already up.
	func open(_ sceneID: String, value: some Codable & Hashable) {
		representation.environment.openWindow(id: sceneID, value: value)
	}

	func dismiss(_ sceneID: String) {
		representation.environment.dismissWindow(id: sceneID)
	}

	func dismiss(_ sceneID: String, value: some Codable & Hashable) {
		representation.environment.dismissWindow(id: sceneID, value: value)
	}

	/// Settings opens on the row the caller names, so the request is in place
	/// before the window is asked for.
	func openSettings(_ selection: SettingsSceneSelection = .default) {
		settingsRequest.open(selection)
		representation.environment.openSettings()
	}
}
