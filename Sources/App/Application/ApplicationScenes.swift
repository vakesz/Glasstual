/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

enum ApplicationSceneID {
	static let about = "about"
	static let channelBanList = "channel-ban-list"
	static let channelSpotlight = "channel-spotlight"
	static let fileTransfers = "file-transfers"
	static let onboarding = "onboarding"
	static let serverChannelList = "server-channel-list"
	static let serverHighlightList = "server-highlight-list"
}

/** What one keyed scene has open, one session per window.

 Every such scene wants the same three things: the session a window already has,
 a new one where there is none, and the session back when the window goes so the
 caller can close it. Each of them used to spell all three out. */
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

/// Installs SwiftUI scenes while the process lifecycle is still hosted by the
/// existing application delegate. Scene registration is the migration seam:
/// each window can move to SwiftUI without creating a second application root.
@MainActor
final class ApplicationScenes {
	private let settingsRequest = SettingsSceneRequest()
	private var channelSpotlightModel: ChannelSpotlightModel?
	private var serverChannelLists = SceneSessions<String, ServerChannelList>()
	private var serverHighlightLists = SceneSessions<String, ServerHighlightList>()
	/// Observable, so replacing the ban list redraws a window already open on
	/// another channel's.
	let channelBanListWindowState = ChannelBanListWindowState()

	private lazy var aboutRepresentation = NSHostingSceneRepresentation {
		AboutScene()
	}

	private lazy var onboardingRepresentation = NSHostingSceneRepresentation {
		OnboardingScene()
	}

	private lazy var channelSpotlightRepresentation = NSHostingSceneRepresentation { [unowned self] in
		ChannelSpotlightScene(scenes: self)
	}

	private lazy var fileTransferRepresentation = NSHostingSceneRepresentation {
		FileTransferListScene(center: AppServices.fileTransfers)
	}

	private lazy var channelBanListRepresentation = NSHostingSceneRepresentation { [unowned self] in
		ChannelBanListScene(scenes: self)
	}

	private lazy var serverChannelListRepresentation = NSHostingSceneRepresentation { [unowned self] in
		ServerChannelListScene(scenes: self)
	}

	private lazy var serverHighlightListRepresentation = NSHostingSceneRepresentation { [unowned self] in
		ServerHighlightListScene(scenes: self)
	}

	private lazy var settingsRepresentation = NSHostingSceneRepresentation { [unowned self] in
		SettingsScene(request: settingsRequest)
	}

	private var isInstalled = false

	func install(in application: NSApplication) {
		guard isInstalled == false else { return }
		isInstalled = true
		application.addSceneRepresentation(aboutRepresentation)
		application.addSceneRepresentation(channelBanListRepresentation)
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
		if let channelSpotlightModel {
			channelSpotlightModel.reloadResults()
		} else {
			channelSpotlightModel = ChannelSpotlightModel()
		}
		channelSpotlightRepresentation.environment.openWindow(id: ApplicationSceneID.channelSpotlight)
	}

	func openFileTransfers() {
		fileTransferRepresentation.environment.openWindow(id: ApplicationSceneID.fileTransfers)
	}

	func closeFileTransfers() {
		fileTransferRepresentation.environment.dismissWindow(id: ApplicationSceneID.fileTransfers)
	}

	func currentChannelSpotlightModel() -> ChannelSpotlightModel? {
		channelSpotlightModel
	}

	func channelSpotlightDidClose() {
		channelSpotlightModel?.close()
		channelSpotlightModel = nil
	}

	func openServerChannelList(for client: Client) {
		let clientIdentifier = client.uniqueIdentifier
		serverChannelLists.open(clientIdentifier) { ServerChannelList(client: client) }.beginRefresh()
		serverChannelListRepresentation.environment.openWindow(
			id: ApplicationSceneID.serverChannelList,
			value: clientIdentifier
		)
	}

	/** The channel list open for a client, if there is one.

	 Only a lookup. Protocol replies and the scene body both ask here, and a
	 lookup that made a missing list sent the server another `LIST` for
	 every row still arriving after the window closed. Opening the window is
	 the one path that makes a list and asks for a listing. */
	func serverChannelList(for clientIdentifier: String) -> ServerChannelList? {
		serverChannelLists[clientIdentifier]
	}

	func closeServerChannelList(for clientIdentifier: String) {
		serverChannelLists.close(clientIdentifier)?.close()
		serverChannelListRepresentation.environment.dismissWindow(
			id: ApplicationSceneID.serverChannelList,
			value: clientIdentifier
		)
	}

	func serverChannelListDidClose(for clientIdentifier: String) {
		serverChannelLists.close(clientIdentifier)?.close()
	}

	/** Opens one channel's ban list, replacing whatever the window was
	 showing.

	 A window rather than a sheet, so the channel the list is about can be read
	 and typed into while its bans are being looked over. The mode query that
	 fills it is sent by the caller, so the session is in place before the first
	 reply can arrive. */
	func openChannelBanList(entryType: ChannelBanListEntryType, in channel: Channel) {
		guard let session = ChannelBanListSession(entryType: entryType, in: channel) else { return }
		channelBanListWindowState.session = session
		channelBanListRepresentation.environment.openWindow(id: ApplicationSceneID.channelBanList)
	}

	func currentChannelBanListSession() -> ChannelBanListSession? {
		channelBanListWindowState.session
	}

	func channelBanListDidClose() {
		channelBanListWindowState.session = nil
	}

	/// Closes the ban list when the channel or connection it is about goes
	/// away, which is what the sheet it replaced got from the main window.
	func closeChannelBanList(matching isStale: (ChannelBanListSession) -> Bool) {
		guard let session = channelBanListWindowState.session, isStale(session) else { return }
		channelBanListWindowState.session = nil
		channelBanListRepresentation.environment.dismissWindow(id: ApplicationSceneID.channelBanList)
	}

	func openServerHighlightList(for client: Client) {
		let clientIdentifier = client.uniqueIdentifier
		_ = serverHighlightLists.open(clientIdentifier) { ServerHighlightList(client: client) }
		serverHighlightListRepresentation.environment.openWindow(
			id: ApplicationSceneID.serverHighlightList,
			value: clientIdentifier
		)
	}

	/// The highlight list of a window that is open, and nothing more: a highlight
	/// logged with no list showing has nowhere to go.
	func visibleServerHighlightList(for clientIdentifier: String) -> ServerHighlightList? {
		serverHighlightLists[clientIdentifier]
	}

	func serverHighlightList(for clientIdentifier: String) -> ServerHighlightList? {
		if let list = serverHighlightLists[clientIdentifier] {
			return list
		}
		guard let client = AppServices.clientDirectory?.findClient(withId: clientIdentifier) else {
			return nil
		}

		return serverHighlightLists.open(clientIdentifier) { ServerHighlightList(client: client) }
	}

	/// The list of a connection that is being taken away has nothing left to
	/// jump into, so the window goes with it.
	func closeServerHighlightList(for clientIdentifier: String) {
		guard serverHighlightLists.close(clientIdentifier) != nil else { return }
		serverHighlightListRepresentation.environment.dismissWindow(
			id: ApplicationSceneID.serverHighlightList,
			value: clientIdentifier
		)
	}

	func serverHighlightListDidClose(for clientIdentifier: String) {
		serverHighlightLists.close(clientIdentifier)
	}

	func openSettings(_ selection: SettingsSceneSelection = .default) {
		settingsRequest.open(selection)
		settingsRepresentation.environment.openSettings()
	}
}
