// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Security
import SecurityInterface
import SwiftUI

@MainActor
final class ServerPropertiesSheet: SheetSession, SessionScoped, ServerPropertiesCommands {
	private(set) var session: ServerSession?
	private(set) var sessionId: String?
	let model: ServerPropertiesModel

	private let notifications = NotificationSubscriptions()
	private var saveTask: Task<Void, Never>?
	var credentialPersistence = KeychainPersistence.shared
	var settingsSaves = SettingsSaveQueue.shared
	let certificateSelection = ClientCertificateSelection()
	private var certificatePanelRequest: UUID?
	/* Weak: the window's presentation chain owns a sheet while it is up, so a
	 child that has been dismissed reads as `nil` here without a callback to
	 clear it. These four exist only to take the children down with the parent. */
	private weak var addressBookSheet: AddressBookEntrySheet?
	private weak var channelSheet: ChannelPropertiesSheet?
	private weak var highlightSheet: HighlightRuleSheet?
	private weak var serverEndpointSheet: ServerEndpointListSheet?
	private weak var clientCertificatePanel: SFChooseIdentityPanel?

	/// The configuration the person accepted.
	private let onSave: (ServerConfig) -> Void

	init(session: ServerSession?, onSave: @escaping (ServerConfig) -> Void) {
		self.onSave = onSave
		self.session = session
		sessionId = session?.uniqueIdentifier
		if let session {
			session.updateStoredConfiguration()
			model = ServerPropertiesModel(config: session.config)
		} else {
			// A new connection starts from the network list rather than a blank form.
			model = ServerPropertiesModel(config: ServerConfig(), offersTemplates: true)
		}
		super.init(window: nil)
		installSheet()
		addConfigurationDidChangeObserver()
	}

	private func installSheet() {
		/* No frame here: `ServerPropertiesView` declares the sheet's minimum and
		 ideal size. Two owners meant the host asked for less than the content
		 demanded, and the sheet clipped both edges of it. */
		setContent(ServerPropertiesView(model: model, commands: self))
	}

	/// Opens the sheet at the pane a menu asked for, on whatever that pane
	/// needs to start on.
	func start(at destination: ServerPropertiesDestination = .default) {
		model.selection = switch destination {
		case .default: .general
		case .addressBook, .newIgnoreEntry, .editIgnoreEntry: .addressBook
		}
		startSheet()

		switch destination {
		case .default, .addressBook:
			break
		case let .newIgnoreEntry(hostmask):
			addIgnoreAddressBookEntry(hostmask: hostmask)
		case let .editIgnoreEntry(entry):
			model.selectedAddressBookEntryID = entry.uniqueIdentifier
			editAddressBookEntry()
		}
	}

	override func submit() {
		guard !model.isSaving else { return }
		let pendingCertificate = certificateSelection.isResolvingReference ? certificateSelection.task : nil
		if pendingCertificate == nil {
			certificateSelection.cancel()
		}
		model.isSaving = true
		saveTask = settingsSaves.submit { [self] in
			await pendingCertificate?.value
			guard let submitted = model.submittedConfig() else {
				model.isSaving = false
				saveTask = nil
				return false
			}
			let write = credentialPersistence.enqueue(submitted.pendingKeychainEdits, retainsFailureForTermination: false)
			do {
				try await write.value
				let edits = submitted.pendingKeychainEdits
				var saved = submitted
				saved.acknowledgeKeychainEdits(edits)
				session?.sessionCredentials.apply(edits)
				model.config = saved
				removeConfigurationDidChangeObserver()
				closeChildSheets()
				onSave(saved)
				finishSaving()
				return true
			} catch {
				model.isSaving = false
				saveTask = nil
				KeychainAlerts.showFailure(error)
				return false
			}
		}
	}

	private func finishSaving() {
		saveTask = nil
		model.isSaving = false
		super.submit()
	}

	override func cancel() {
		guard !model.isSaving else { return }
		saveTask?.cancel()
		saveTask = nil
		model.isSaving = false
		removeConfigurationDidChangeObserver()
		closeChildSheets()
		super.cancel()
	}

	func editEndpoints() {
		guard let servers = model.serverListForEditing() else { return }
		let sheet = ServerEndpointListSheet(window: window) { [weak self] serverList in
			self?.model.applyServerList(serverList)
		}
		sheet.start(with: servers)
		serverEndpointSheet = sheet
	}

	func addChannel() {
		presentChannelSheet(config: nil)
	}

	func editChannel() {
		guard let id = model.selectedChannelID,
		      let channel = model.config.conversationList.first(where: { $0.uniqueIdentifier == id }) else { return }
		presentChannelSheet(config: channel)
	}

	/// A channel raised from here is part of this sheet's pending edit, so its
	/// keychain items are written when this sheet is accepted rather than when
	/// the channel editor is.
	private func presentChannelSheet(config: ConversationConfig?) {
		let sheet = ChannelPropertiesSheet(
			config: config,
			onSession: session,
			savesCredentials: false
		) { [weak self] channelConfig in
			self?.applyChannel(channelConfig)
		}
		sheet.window = window
		sheet.startSheet()
		channelSheet = sheet
	}

	func deleteChannel() {
		guard let id = model.selectedChannelID else { return }
		model.config.conversationList.removeAll { $0.uniqueIdentifier == id }
		model.selectedChannelID = nil
	}

	private func applyChannel(_ config: ConversationConfig) {
		if let index = model.config.conversationList.firstIndex(where: { $0.uniqueIdentifier == config.uniqueIdentifier }) {
			model.config.conversationList[index] = config
		} else {
			model.config.conversationList.append(config)
		}
		model.selectedChannelID = config.uniqueIdentifier
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
		sheet.window = window
		sheet.startSheet()
		highlightSheet = sheet
	}

	func deleteHighlight() {
		guard let id = model.selectedHighlightID else { return }
		model.config.highlightList.removeAll { $0.uniqueIdentifier == id }
		model.selectedHighlightID = nil
	}

	private func applyHighlight(_ config: HighlightMatchCondition) {
		if let index = model.config.highlightList
			.firstIndex(where: { $0.uniqueIdentifier == config.uniqueIdentifier })
		{
			model.config.highlightList[index] = config
		} else {
			model.config.highlightList.append(config)
		}
		model.selectedHighlightID = config.uniqueIdentifier
	}

	func applyTemplate() {
		model.applySelectedTemplate()
	}

	func addIgnoreEntry() {
		addIgnoreAddressBookEntry(hostmask: nil)
	}

	private func addIgnoreAddressBookEntry(hostmask: String?) {
		guard let hostmask else {
			presentAddressBookSheet(AddressBookEntrySheet(entryType: .ignore, onSave: applyAddressBookEntry))
			return
		}
		presentAddressBookSheet(AddressBookEntrySheet(
			entry: .newIgnoreEntry(forHostmask: hostmask),
			onSave: applyAddressBookEntry
		))
	}

	func addTrackingEntry() {
		presentAddressBookSheet(AddressBookEntrySheet(
			entryType: .userTracking,
			onSave: applyAddressBookEntry
		))
	}

	func editAddressBookEntry() {
		guard let id = model.selectedAddressBookEntryID,
		      let entry = model.config.ignoreList.first(where: { $0.uniqueIdentifier == id }) else { return }
		presentAddressBookSheet(AddressBookEntrySheet(entry: entry, onSave: applyAddressBookEntry))
	}

	private func presentAddressBookSheet(_ sheet: AddressBookEntrySheet) {
		sheet.window = window
		sheet.startSheet()
		addressBookSheet = sheet
	}

	func deleteAddressBookEntry() {
		guard let id = model.selectedAddressBookEntryID else { return }
		model.config.ignoreList.removeAll { $0.uniqueIdentifier == id }
		model.selectedAddressBookEntryID = nil
	}

	private func applyAddressBookEntry(_ entry: AddressBookEntry) {
		if let index = model.config.ignoreList.firstIndex(where: { $0.uniqueIdentifier == entry.uniqueIdentifier }) {
			model.config.ignoreList[index] = entry
		} else {
			model.config.ignoreList.append(entry)
		}
		model.selectedAddressBookEntryID = entry.uniqueIdentifier
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

	private func presentCertificatePicker(_ identities: [SecIdentity]) {
		guard !identities.isEmpty else {
			Alerts.alertSheet(
				title: String(localized: .ServerProperties.noCertificatesAvailable),
				body: String(localized: .ServerProperties.thereAreNoCertificates),
				defaultButton: PromptStrings.Action.confirmation
			)
			return
		}
		guard let panel = SFChooseIdentityPanel.shared() else { return }
		clientCertificatePanel = panel
		panel.setInformativeText(String(localized: .ServerProperties.selectACertificateToSendWhen))
		panel.setAlternateButtonTitle(PromptStrings.Action.cancel)
		guard let hostWindow = AppServices.delegate.mainWindow?.frontmostAttachedSheet else { return }
		let request = UUID()
		certificatePanelRequest = request
		panel.beginSheet(
			for: hostWindow,
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
		notifications.observe(.serverSessionConfigWasUpdated, object: session) { [weak self] notification in
			self?.underlyingConfigurationChanged(notification)
		}
	}

	private func removeConfigurationDidChangeObserver() {
		notifications.cancelAll()
	}

	/** The connection was reconfigured from somewhere else while the sheet is
	 open.

	 The alert is a sheet on the window this sheet is already on, so it arrives
	 over the edits it is asking about. Keeping what is typed is the default;
	 reloading is the destructive answer, because it throws those edits away. */
	private func underlyingConfigurationChanged(_ notification: Notification) {
		guard let session = notification.object as? ServerSession else { return }
		Alerts.alertSheet(
			title: String(localized: .ServerProperties.thisConnectionsConfigurationHasChangedDo),
			body: String(localized: .ServerProperties.youWillLooseUnsavedChangesIf),
			defaultButton: PromptStrings.Action.cancel,
			alternateButton: String(localized: .ServerProperties.reloadButton),
			destructiveButton: .alternate
		) { [weak self] outcome in
			guard outcome.response == .alternate, let self else { return }
			cancelCertificateSelection()
			session.updateStoredConfiguration()
			model.replace(with: session.config)
		}
	}

	private func cancelCertificateSelection() {
		certificateSelection.cancel()
		certificatePanelRequest = nil
		if let panel = clientCertificatePanel {
			clientCertificatePanel = nil
			panel.sheetParent?.endSheet(panel, returnCode: .cancel)
		}
	}

	private func closeChildSheets() {
		cancelCertificateSelection()
		addressBookSheet?.cancel()
		channelSheet?.cancel()
		highlightSheet?.cancel()
		serverEndpointSheet?.cancel()
	}

	override func sheetDidEnd() {
		closeChildSheets()
		removeConfigurationDidChangeObserver()
	}
}
