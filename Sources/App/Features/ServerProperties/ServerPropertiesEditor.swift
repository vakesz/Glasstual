// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Security
import SecurityInterface
import SwiftUI

/** What one Server Properties window edits, and everything it raises.

 One editor per connection, kept by ``ServerPropertiesWindows`` under the
 connection's identifier, which is also what the window is opened with: asking
 for the same connection's properties again brings that window forward with
 its edits. A new connection gets an editor of its own under the identifier its
 configuration was made with, and its window closes once it is saved.

 The window is not modal, so the edits live until they are saved or reverted.
 Closing the window while there are any asks whether to save them, as a
 document window does, and quitting asks the same of every edited window. */
@MainActor
@Observable
final class ServerPropertiesEditor: NSObject, SessionScoped, ServerPropertiesCommands, SheetHost {
	@ObservationIgnored private(set) var session: ServerSession?
	@ObservationIgnored private(set) var sessionId: String?
	let model: ServerPropertiesModel
	/// The editors this window raises over itself: endpoints, channels,
	/// highlights and address book entries.
	let sheetModel = MainWindowSheetModel()
	/// What the window is opened, found and restored by.
	let windowID: String

	/// Set when the connection's configuration changed underneath unsaved
	/// edits, while the window asks whether to reload.
	var asksToReload = false
	/// Set when the window should go: a new connection was saved, or a new
	/// connection was cancelled.
	private(set) var closeRequested = false
	/// Set while the window asks what to do with its edits before it closes.
	@ObservationIgnored var isReviewingUnsavedChanges = false
	/// The window's close review, which the window hands over once it is on
	/// screen: what the editor's questions attach to, and what closes it.
	@ObservationIgnored weak var closeReview: WindowCloseReview?

	@ObservationIgnored private let notifications = NotificationSubscriptions()
	@ObservationIgnored var credentialPersistence = KeychainPersistence.shared
	@ObservationIgnored var settingsSaves = SettingsSaveQueue.shared
	@ObservationIgnored let certificateSelection = ClientCertificateSelection()
	@ObservationIgnored private var certificatePanelRequest: UUID?
	@ObservationIgnored private weak var clientCertificatePanel: SFChooseIdentityPanel?

	/// The configuration the person saved, and the connection it belongs to:
	/// `nil` for a connection the save is about to create.
	@ObservationIgnored private let onSave: @MainActor (ServerConfig, ServerSession?) -> Void

	init(session: ServerSession?, onSave: @escaping @MainActor (ServerConfig, ServerSession?) -> Void) {
		self.onSave = onSave
		self.session = session
		sessionId = session?.uniqueIdentifier
		if let session {
			session.updateStoredConfiguration()
			model = ServerPropertiesModel(config: session.config)
			model.bouncerNetworks = BouncerNetworksModel(session: session)
			model.profile = ServerProfileModel(session: session)
		} else {
			// A new connection starts from the network list rather than a blank form.
			var config = ServerConfig()
			config.serverList = [ServerEndpoint(
				serverPort: UInt16(ConnectionDefaults.serverPortSecure),
				prefersSecuredConnection: true
			)]
			model = ServerPropertiesModel(config: config, offersTemplates: true)
		}
		windowID = model.config.uniqueIdentifier
		super.init()
		addConfigurationDidChangeObserver()
	}

	/// The window's title: the connection, or New Server for one that does
	/// not exist yet.
	var windowTitle: String {
		guard model.isNewServer == false else {
			return String(localized: .ServerProperties.newServerWindowTitle)
		}
		let name = model.config.connectionName.trimmingCharacters(in: .whitespacesAndNewlines)
		return name.isEmpty ? String(localized: .ServerProperties.serverPropertiesWindowGroupTitle) : name
	}

	/// The pane being shown, and whether there is anything left to save, the
	/// way a document window says Edited.
	var windowSubtitle: String {
		let pane = String(localized: model.selection.title)
		guard model.hasUnsavedChanges, model.templatePicker == nil else { return pane }
		return String(localized: .ServerProperties.windowSubtitleEdited(pane))
	}

	/** Saves the edits. The window stays open on an existing connection, as a
	 saved document does; a new connection's window closes, because what it
	 was for is done. */
	func submit() {
		submit(completion: nil)
	}

	/// Saves the edits and reports whether they were saved. A refused or
	/// failed save leaves the edits, and the window, where they are.
	func save() async -> Bool {
		await withCheckedContinuation { continuation in
			submit { continuation.resume(returning: $0) }
		}
	}

	private func submit(completion: ((Bool) -> Void)?) {
		guard !model.isSaving else {
			completion?(false)
			return
		}
		let pendingCertificate = certificateSelection.isResolvingReference ? certificateSelection.task : nil
		if pendingCertificate == nil {
			certificateSelection.cancel()
		}
		model.isSaving = true
		settingsSaves.submit { [self] in
			await pendingCertificate?.value
			guard var submitted = model.submittedConfig() else {
				model.isSaving = false
				completion?(false)
				return false
			}
			/* The Profile pane changes the server's profile live, outside Save,
			 and the People window changes the address book the same way, so
			 what the session holds now is what to keep of both. */
			if let session {
				submitted.serverProfile = session.config.serverProfile
				submitted.ignoreList = session.config.ignoreList
			}
			let write = credentialPersistence.enqueue(submitted.pendingKeychainEdits, retainsFailureForTermination: false)
			do {
				try await write.value
				let edits = submitted.pendingKeychainEdits
				var saved = submitted
				saved.acknowledgeKeychainEdits(edits)
				session?.sessionCredentials.apply(edits)
				/* Marked saved before the connection is told, so the update the
				 save itself causes reads as nothing left to reload. */
				model.markSaved(saved)
				onSave(saved, session)
				model.isSaving = false
				if session == nil {
					cancelCertificateSelection()
					closeRequested = true
				} else {
					Task { await model.loadSecrets() }
				}
				completion?(true)
				return true
			} catch {
				model.isSaving = false
				/* The failure is about this window's edits, so it is told on
				 this window, over them. */
				Alerts.present(KeychainAlerts.failureAlert(error, canRetry: false), on: alertPresentation)
				completion?(false)
				return false
			}
		}
	}

	/** Throws the edits away: a new connection's window closes, and an existing
	 connection's goes back to what is saved. Only ever the person's own
	 choice, from Revert or Cancel. */
	func cancel() {
		guard !model.isSaving else { return }
		guard let session else {
			cancelCertificateSelection()
			closeRequested = true
			return
		}
		reload(from: session)
	}

	private func reload(from session: ServerSession) {
		cancelCertificateSelection()
		session.updateStoredConfiguration()
		let selection = model.selection
		model.replace(with: session.config)
		model.selection = selection
		Task { await model.loadSecrets() }
	}

	func editEndpoints() {
		guard let servers = model.serverListForEditing() else { return }
		let sheet = ServerEndpointListSheet(window: nil) { [weak self] serverList in
			self?.model.applyServerList(serverList)
		}
		sheet.host = self
		sheet.start(with: servers)
	}

	func addChannel() {
		presentChannelSheet(config: nil)
	}

	func editChannel() {
		guard let id = model.selectedChannelID,
		      let channel = model.config.conversationList.first(where: { $0.uniqueIdentifier == id }) else { return }
		presentChannelSheet(config: channel)
	}

	/// A channel raised from here is part of this window's pending edit, so
	/// its keychain items are written when the window is saved rather than
	/// when the channel editor is.
	private func presentChannelSheet(config: ConversationConfig?) {
		let sheet = ChannelPropertiesSheet(
			config: config,
			onSession: session,
			siblingNames: ChannelPropertiesSheet.siblingNames(
				in: model.config.conversationList,
				excluding: config?.uniqueIdentifier
			),
			savesCredentials: false
		) { [weak self] channelConfig in
			self?.applyChannel(channelConfig)
		}
		presentEditor(sheet)
	}

	func deleteChannel() {
		guard let id = model.selectedChannelID else { return }
		model.config.conversationList.removeAll { $0.uniqueIdentifier == id }
		model.selectedChannelID = nil
	}

	private func applyChannel(_ entry: ConversationConfig) {
		upsert(entry, id: \.uniqueIdentifier, in: \.conversationList, selecting: \.selectedChannelID)
	}

	func addHighlight() {
		presentHighlightSheet(config: nil)
	}

	func editHighlight() {
		guard let id = model.selectedHighlightID,
		      let entry = model.config.highlightList.first(where: { $0.uniqueIdentifier == id }) else { return }
		presentHighlightSheet(config: entry)
	}

	private func presentHighlightSheet(config: HighlightMatchCondition?) {
		let sheet = HighlightRuleSheet(config: config, channels: model.config.conversationList) { [weak self] entry in
			self?.applyHighlight(entry)
		}
		presentEditor(sheet)
	}

	func deleteHighlight() {
		guard let id = model.selectedHighlightID else { return }
		model.config.highlightList.removeAll { $0.uniqueIdentifier == id }
		model.selectedHighlightID = nil
	}

	private func applyHighlight(_ entry: HighlightMatchCondition) {
		upsert(entry, id: \.uniqueIdentifier, in: \.highlightList, selecting: \.selectedHighlightID)
	}

	func applyTemplate() {
		model.applySelectedTemplate()
	}

	/// Raises a child editor as a sheet on this window.
	private func presentEditor(_ sheet: SheetSession) {
		sheet.host = self
		sheet.startSheet()
	}

	/// Replaces the entry that shares `entry`'s identifier, or appends it, and
	/// selects it.
	private func upsert<Entry>(
		_ entry: Entry,
		id: KeyPath<Entry, String>,
		in list: WritableKeyPath<ServerConfig, [Entry]>,
		selecting selection: ReferenceWritableKeyPath<ServerPropertiesModel, String?>
	) {
		if let index = model.config[keyPath: list].firstIndex(where: { $0[keyPath: id] == entry[keyPath: id] }) {
			model.config[keyPath: list][index] = entry
		} else {
			model.config[keyPath: list].append(entry)
		}
		model[keyPath: selection] = entry[keyPath: id]
	}

	/// Copies the command that registers the fingerprint with NickServ, which
	/// is what the button beside a fingerprint has always put on the pasteboard
	/// — the button used to say only "Copy".
	func copyNickServCommand(for fingerprint: String) {
		guard model.config.identityClientSideCertificate != nil else { return }
		NSPasteboard.general.stringContent = "/msg NickServ cert add \(fingerprint)"
	}

	func resetCertificate() {
		cancelCertificateSelection()
		model.config.identityClientSideCertificate = nil
	}

	func chooseCertificate() {
		cancelCertificateSelection()
		certificateSelection.chooseIdentities { [weak self] identities in
			self?.presentCertificatePicker(identities)
		}
	}

	/// The notice that the keychain holds no certificate to choose.
	static var noCertificatesRequest: AlertRequest {
		AlertRequest(
			title: String(localized: .ServerProperties.noCertificatesAvailable),
			body: String(localized: .ServerProperties.thereAreNoCertificates),
			defaultButton: PromptStrings.Action.confirmation
		)
	}

	private func presentCertificatePicker(_ identities: [SecIdentity]) {
		guard !identities.isEmpty else {
			Alerts.present(Self.noCertificatesRequest, on: alertPresentation)
			return
		}
		guard let panel = SFChooseIdentityPanel.shared() else { return }
		clientCertificatePanel = panel
		panel.setInformativeText(String(localized: .ServerProperties.selectACertificateToSendWhen))
		panel.setAlternateButtonTitle(PromptStrings.Action.cancel)
		/* The panel hangs off this window, the one the button was pressed in,
		 whichever window is key by the time the keychain has answered. */
		guard let parent = hostWindow?.frontmostAttachedSheet else {
			clientCertificatePanel = nil
			return
		}
		let request = UUID()
		certificatePanelRequest = request
		panel.beginSheet(
			for: parent,
			modalDelegate: self,
			didEnd: #selector(identityPanelDidEnd(_:returnCode:contextInfo:)),
			contextInfo: Unmanaged.passRetained(request as NSUUID).toOpaque(),
			identities: identities,
			message: String(localized: .ServerProperties.chooseAnIdentity)
		)
	}

	@objc private func identityPanelDidEnd(
		_ panel: SFChooseIdentityPanel,
		returnCode: Int,
		contextInfo: UnsafeMutableRawPointer?
	) {
		guard let contextInfo else { return }
		let request = Unmanaged<NSUUID>.fromOpaque(contextInfo).takeRetainedValue() as UUID
		guard certificatePanelRequest == request, clientCertificatePanel === panel else { return }
		certificatePanelRequest = nil
		clientCertificatePanel = nil
		guard returnCode == NSApplication.ModalResponse.OK.rawValue,
		      let identity = panel.identity()?.takeUnretainedValue() else { return }
		var certificate: SecCertificate?
		guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { return }
		certificateSelection.resolveReference {
			await ClientCertificateLoader.persistentReference(for: certificate)
		} apply: { [weak self] reference in
			guard let self else { return }
			model.config.identityClientSideCertificate = reference
			model.primaryServerIsSecured = true
		}
	}

	private func addConfigurationDidChangeObserver() {
		guard let session else { return }
		notifications.observe(ServerSessionConfigWasUpdated.self, of: session) { [weak self] message in
			self?.underlyingConfigurationChanged(message)
		}
	}

	private func removeConfigurationDidChangeObserver() {
		notifications.cancelAll()
	}

	/** The connection was reconfigured from somewhere else -- `/serverconfig`,
	 an import, a bouncer -- while the window is open.

	 With nothing unsaved the window simply follows. With edits, the window asks
	 over those edits; keeping them is the default and the safe answer, and
	 reloading is the destructive one, because it throws them away. */
	private func underlyingConfigurationChanged(_ message: ServerSessionConfigWasUpdated) {
		let session = message.subject
		/* Compared with what the window last loaded or saved, not with the
		 edits: the edits always differ, and are not what changed. */
		let saved = model.savedEditState?.config ?? model.config
		guard Self.changesEditedConfiguration(from: saved, to: session.config) else { return }
		guard model.hasUnsavedChanges else {
			reload(from: session)
			return
		}
		asksToReload = true
	}

	/** Whether `updated` changes anything this window edits, from the
	 configuration it last loaded or saved. The address book
	 is the People window's and the server profile is the Profile pane's, and
	 both change live, outside Save, which keeps whatever the connection holds;
	 a change to either alone is not a change to the configuration here. */
	static func changesEditedConfiguration(from saved: ServerConfig, to updated: ServerConfig) -> Bool {
		var updated = updated
		updated.ignoreList = saved.ignoreList
		updated.serverProfile = saved.serverProfile
		return updated != saved
	}

	/// The answer to the reload question: `true` throws the edits away.
	func answerReloadQuestion(reload shouldReload: Bool) {
		asksToReload = false
		guard shouldReload, let session else { return }
		reload(from: session)
	}

	private func cancelCertificateSelection() {
		certificateSelection.cancel()
		certificatePanelRequest = nil
		if let panel = clientCertificatePanel {
			clientCertificatePanel = nil
			panel.sheetParent?.endSheet(panel, returnCode: .cancel)
		}
	}

	/// The window has gone, however it went: its editors go with it.
	func windowDidClose() {
		// An accepted save owns its pending reference even after the window closes.
		if !model.isSaving {
			cancelCertificateSelection()
		}
		sheetModel.dismissPresentedSheet()
		removeConfigurationDidChangeObserver()
	}
}
