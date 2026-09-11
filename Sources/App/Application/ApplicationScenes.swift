/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

enum ApplicationSceneID {
	static let about = "about"
	static let channelAccessList = "channel-access-list"
	static let channelSpotlight = "channel-spotlight"
	static let fileTransfers = "file-transfers"
	static let onboarding = "onboarding"
	static let serverChannelList = "server-channel-list"
	static let serverHighlightList = "server-highlight-list"
}

/// Installs SwiftUI scenes while the process lifecycle is still hosted by the
/// existing application delegate. Scene registration is the migration seam:
/// each window can move to SwiftUI without creating a second application root.
@MainActor
final class ApplicationScenes {
	private let settingsRequest = SettingsSceneRequest()
	private var channelSpotlightSession: ChannelSpotlightSession?
	private var serverChannelListSessions: [String: ServerChannelListSession] = [:]
	private var serverHighlightListSessions: [String: ServerHighlightListSession] = [:]
	/// Observable, so replacing the access list redraws a window already open on
	/// another channel's.
	let channelAccessListWindowState = ChannelAccessListWindowState()

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

	private lazy var channelAccessListRepresentation = NSHostingSceneRepresentation { [unowned self] in
		ChannelAccessListApplicationScene(scenes: self)
	}

	private lazy var serverChannelListRepresentation = NSHostingSceneRepresentation { [unowned self] in
		ServerChannelListApplicationScene(scenes: self)
	}

	private lazy var serverHighlightListRepresentation = NSHostingSceneRepresentation { [unowned self] in
		ServerHighlightListApplicationScene(scenes: self)
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
		application.addSceneRepresentation(channelAccessListRepresentation)
		application.addSceneRepresentation(channelSpotlightRepresentation)
		application.addSceneRepresentation(fileTransferRepresentation)
		application.addSceneRepresentation(onboardingRepresentation)
		application.addSceneRepresentation(serverChannelListRepresentation)
		application.addSceneRepresentation(serverHighlightListRepresentation)
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

	/** Opens one channel's access list, replacing whatever the window was
	 showing.

	 The mode query that fills it is sent by the caller, so the session is in
	 place before the first reply can arrive. */
	func openChannelAccessList(entryType: ChannelBanListEntryType, in channel: IRCChannel) {
		guard let session = ChannelAccessListSession(entryType: entryType, in: channel) else { return }
		channelAccessListWindowState.session = session
		channelAccessListRepresentation.environment.openWindow(id: ApplicationSceneID.channelAccessList)
	}

	func currentChannelAccessListSession() -> ChannelAccessListSession? {
		channelAccessListWindowState.session
	}

	func channelAccessListDidClose() {
		channelAccessListWindowState.session = nil
	}

	/// Closes the access list when the channel or connection it is about goes
	/// away, which is what the sheet it replaced got from the main window.
	func closeChannelAccessList(matching isStale: (ChannelAccessListSession) -> Bool) {
		guard let session = channelAccessListWindowState.session, isStale(session) else { return }
		channelAccessListWindowState.session = nil
		channelAccessListRepresentation.environment.dismissWindow(id: ApplicationSceneID.channelAccessList)
	}

	func openServerHighlightList(for client: IRCClient) {
		let clientIdentifier = client.uniqueIdentifier
		let session = serverHighlightListSessions[clientIdentifier] ?? ServerHighlightListSession(client: client)
		serverHighlightListSessions[clientIdentifier] = session
		serverHighlightListRepresentation.environment.openWindow(
			id: ApplicationSceneID.serverHighlightList,
			value: clientIdentifier
		)
	}

	/// The highlight list of a window that is open, and nothing more: a highlight
	/// logged with no list showing has nowhere to go.
	func openServerHighlightListSession(for clientIdentifier: String) -> ServerHighlightListSession? {
		serverHighlightListSessions[clientIdentifier]
	}

	func serverHighlightList(for clientIdentifier: String) -> ServerHighlightListSession? {
		if let session = serverHighlightListSessions[clientIdentifier] {
			return session
		}
		guard let client = AppController.shared.world?.findClient(withId: clientIdentifier) else {
			return nil
		}
		let session = ServerHighlightListSession(client: client)
		serverHighlightListSessions[clientIdentifier] = session
		return session
	}

	/// The list of a connection that is being taken away has nothing left to
	/// jump into, so the window goes with it.
	func closeServerHighlightList(for clientIdentifier: String) {
		guard serverHighlightListSessions.removeValue(forKey: clientIdentifier) != nil else { return }
		serverHighlightListRepresentation.environment.dismissWindow(
			id: ApplicationSceneID.serverHighlightList,
			value: clientIdentifier
		)
	}

	func serverHighlightListDidClose(for clientIdentifier: String) {
		serverHighlightListSessions.removeValue(forKey: clientIdentifier)
	}

	func openSettings(_ selection: PreferencesSceneSelection = .default) {
		settingsRequest.open(selection)
		settingsRepresentation.environment.openSettings()
	}
}
