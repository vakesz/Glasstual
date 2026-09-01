/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

enum ApplicationSceneID {
	static let about = "about"
	static let channelSpotlight = "channel-spotlight"
	static let fileTransfers = "file-transfers"
	static let onboarding = "onboarding"
	static let serverChannelList = "server-channel-list"
}

/// Installs SwiftUI scenes while the process lifecycle is still hosted by the
/// existing application delegate. Scene registration is the migration seam:
/// each window can move to SwiftUI without creating a second application root.
@MainActor
final class ApplicationScenes {
	private let settingsRequest = SettingsSceneRequest()
	private var channelSpotlightSession: ChannelSpotlightSession?
	private var serverChannelListSessions: [String: ServerChannelListSession] = [:]
	private lazy var aboutRepresentation = NSHostingSceneRepresentation {
		AboutApplicationScene()
	}

	private lazy var onboardingRepresentation = NSHostingSceneRepresentation {
		OnboardingApplicationScene()
	}

	private lazy var channelSpotlightRepresentation = NSHostingSceneRepresentation { [unowned self] in
		ChannelSpotlightApplicationScene(scenes: self)
	}

	private lazy var fileTransferRepresentation = NSHostingSceneRepresentation {
		FileTransferApplicationScene(center: SharedApplication.sharedFileTransferCenter())
	}

	private lazy var serverChannelListRepresentation = NSHostingSceneRepresentation { [unowned self] in
		ServerChannelListApplicationScene(scenes: self)
	}

	private lazy var settingsRepresentation = NSHostingSceneRepresentation {
		Settings {
			PreferencesSceneRoot(request: settingsRequest)
		}
	}

	private var isInstalled = false

	func install(in application: NSApplication) {
		guard isInstalled == false else { return }
		isInstalled = true
		application.addSceneRepresentation(aboutRepresentation)
		application.addSceneRepresentation(channelSpotlightRepresentation)
		application.addSceneRepresentation(fileTransferRepresentation)
		application.addSceneRepresentation(onboardingRepresentation)
		application.addSceneRepresentation(serverChannelListRepresentation)
		application.addSceneRepresentation(settingsRepresentation)
	}

	func openAbout() {
		aboutRepresentation.environment.openWindow(id: ApplicationSceneID.about)
	}

	func openOnboarding() {
		onboardingRepresentation.environment.openWindow(id: ApplicationSceneID.onboarding)
	}

	func openChannelSpotlight() {
		if let channelSpotlightSession {
			channelSpotlightSession.reloadResults()
		} else {
			channelSpotlightSession = ChannelSpotlightSession()
		}
		channelSpotlightRepresentation.environment.openWindow(id: ApplicationSceneID.channelSpotlight)
	}

	func openFileTransfers() {
		fileTransferRepresentation.environment.openWindow(id: ApplicationSceneID.fileTransfers)
	}

	func closeFileTransfers() {
		fileTransferRepresentation.environment.dismissWindow(id: ApplicationSceneID.fileTransfers)
	}

	func currentChannelSpotlightSession() -> ChannelSpotlightSession? {
		channelSpotlightSession
	}

	func channelSpotlightDidClose() {
		channelSpotlightSession?.close()
		channelSpotlightSession = nil
	}

	func openServerChannelList(for client: IRCClient) {
		let clientIdentifier = client.uniqueIdentifier
		let session = serverChannelListSessions[clientIdentifier] ?? ServerChannelListSession(client: client)
		serverChannelListSessions[clientIdentifier] = session
		session.beginRefresh()
		serverChannelListRepresentation.environment.openWindow(
			id: ApplicationSceneID.serverChannelList,
			value: clientIdentifier
		)
	}

	func serverChannelList(for clientIdentifier: String) -> ServerChannelListSession? {
		if let session = serverChannelListSessions[clientIdentifier] {
			return session
		}
		guard let client = AppController.shared.world?.findClient(withId: clientIdentifier) else {
			return nil
		}
		let session = ServerChannelListSession(client: client)
		serverChannelListSessions[clientIdentifier] = session
		session.beginRefresh()
		return session
	}

	func closeServerChannelList(for clientIdentifier: String) {
		serverChannelListSessions.removeValue(forKey: clientIdentifier)?.close()
		serverChannelListRepresentation.environment.dismissWindow(
			id: ApplicationSceneID.serverChannelList,
			value: clientIdentifier
		)
	}

	func serverChannelListDidClose(for clientIdentifier: String) {
		serverChannelListSessions.removeValue(forKey: clientIdentifier)?.close()
	}

	func openSettings(_ selection: PreferencesSceneSelection = .default) {
		settingsRequest.open(selection)
		settingsRepresentation.environment.openSettings()
	}
}
