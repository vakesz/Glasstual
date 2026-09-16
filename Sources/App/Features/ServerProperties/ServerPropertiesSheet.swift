/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Security
import SecurityInterface
import SwiftUI

/// One pane of the connection sheet. Every case is a pane the sidebar lists and
/// the detail view draws: the entry points a menu can open the sheet at are
/// `ServerPropertiesDestination`, which is a different question and used to be
/// mixed in here as two cases nothing could select.
enum ServerPropertiesSelection: CaseIterable, Hashable {
	case addressBook
	case autojoin
	case connectCommands
	case encoding
	case general
	case identity
	case highlights
	case disconnectMessages
	case zncBouncer
	case clientCertificate
	case floodControl
	case networkSocket
	case proxyServer
}

@MainActor
protocol ServerPropertiesSheetDelegate: AnyObject {
	func serverPropertiesSheet(_ sender: ServerPropertiesSheet, onOk config: ClientConfig)
}

@MainActor
final class ServerPropertiesSheet: SheetSession, ClientScoped,
	AddressBookSheetDelegate, ChannelPropertiesSheetDelegate, HighlightEntrySheetDelegate,
	ServerEndpointListSheetDelegate
{
	private(set) var client: Client?
	private(set) var clientId: String?
	let model: ServerPropertiesModel

	private let notifications = NotificationSubscriptions()
	private var saveTask: Task<Void, Never>?
	var credentialPersistence = KeychainPersistence.shared
	let certificateSelection = ClientCertificateSelection()
	private var certificatePanelRequest: UUID?
	/* Weak: the window's presentation chain owns a sheet while it is up, so a
	 child that has been dismissed reads as `nil` here without a callback to
	 clear it. These four exist only to take the children down with the parent. */
	private weak var addressBookSheet: AddressBookSheet?
	private weak var channelSheet: ChannelPropertiesSheet?
	private weak var highlightSheet: HighlightEntrySheet?
	private weak var serverEndpointSheet: ServerEndpointListSheet?
	private weak var clientCertificatePanel: SFChooseIdentityPanel?

	init(client: Client?) {
		self.client = client
		clientId = client?.uniqueIdentifier
		if let client {
			client.updateStoredConfiguration()
			model = ServerPropertiesModel(config: client.config)
		} else {
			// A new connection starts from the network list rather than a blank form.
			model = ServerPropertiesModel(config: ClientConfig(), offersTemplates: true)
		}
		super.init(window: nil)
		installSheet()
		addConfigurationDidChangeObserver()
	}

	private func installSheet() {
		let actions = ServerPropertiesActions(
			submit: { [weak self] in self?.submit() },
			cancel: { [weak self] in self?.cancel() },
			applyTemplate: { [weak self] in self?.model.applySelectedTemplate() },
			editEndpoints: { [weak self] in self?.editServerEndpoints() },
			channels: ServerPropertiesListActions(
				addLabel: ServerPropertiesStrings.ListButton.addChannel,
				add: { [weak self] in self?.addChannel() },
				selected: ServerPropertiesSelectedEntryActions(
					editLabel: ServerPropertiesStrings.ListButton.editChannel,
					edit: { [weak self] in self?.editChannel() },
					removeLabel: ServerPropertiesStrings.ListButton.removeChannel,
					remove: { [weak self] in self?.deleteChannel() }
				)
			),
			highlights: ServerPropertiesListActions(
				addLabel: ServerPropertiesStrings.ListButton.addHighlight,
				add: { [weak self] in self?.addHighlight() },
				selected: ServerPropertiesSelectedEntryActions(
					editLabel: ServerPropertiesStrings.ListButton.editHighlight,
					edit: { [weak self] in self?.editHighlight() },
					removeLabel: ServerPropertiesStrings.ListButton.removeHighlight,
					remove: { [weak self] in self?.deleteHighlight() }
				)
			),
			addressBook: ServerPropertiesAddressBookActions(
				addLabel: ServerPropertiesStrings.ListButton.addAddressBookEntry,
				addIgnore: { [weak self] in self?.addIgnoreAddressBookEntry(hostmask: nil) },
				addTracking: { [weak self] in self?.addTrackingAddressBookEntry() },
				selected: ServerPropertiesSelectedEntryActions(
					editLabel: ServerPropertiesStrings.ListButton.editAddressBookEntry,
					edit: { [weak self] in self?.editAddressBookEntry() },
					removeLabel: ServerPropertiesStrings.ListButton.removeAddressBookEntry,
					remove: { [weak self] in self?.deleteAddressBookEntry() }
				)
			),
			certificate: ServerPropertiesCertificateActions(
				choose: { [weak self] in self?.chooseCertificate() },
				reset: { [weak self] in self?.resetCertificate() },
				copyNickServCommand: { [weak self] value in self?.copyNickServCommand(for: value) }
			)
		)
		/* No frame here: `ServerPropertiesView` declares the sheet's minimum and
		 ideal size. Two owners meant the host asked for less than the content
		 demanded, and the sheet clipped both edges of it. */
		setContent(ServerPropertiesView(model: model, actions: actions))
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
		saveTask = credentialPersistence.submitSettingsSave { [self] in
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
				client?.sessionCredentials.apply(edits)
				model.config = saved
				removeConfigurationDidChangeObserver()
				closeChildSheets()
				(delegate as? any ServerPropertiesSheetDelegate)?.serverPropertiesSheet(self, onOk: saved)
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

	private func editServerEndpoints() {
		guard let servers = model.serverListForEditing() else { return }
		let controller = ServerEndpointListSheet(window: window)
		controller.delegate = self
		controller.start(with: servers)
		serverEndpointSheet = controller
	}

	func serverEndpointListSheet(_: ServerEndpointListSheet, onOk serverList: [Server]) {
		model.applyServerList(serverList)
	}

	private func addChannel() {
		presentChannelSheet(config: nil)
	}

	private func editChannel() {
		guard let id = model.selectedChannelID,
		      let channel = model.config.channelList.first(where: { $0.uniqueIdentifier == id }) else { return }
		presentChannelSheet(config: channel)
	}

	private func presentChannelSheet(config: ChannelConfig?) {
		let controller = ChannelPropertiesSheet(config: config, onClient: client)
		controller.delegate = self
		controller.window = window
		controller.start()
		channelSheet = controller
	}

	private func deleteChannel() {
		guard let id = model.selectedChannelID else { return }
		model.config.channelList.removeAll { $0.uniqueIdentifier == id }
		model.selectedChannelID = nil
	}

	func channelPropertiesSheet(_: ChannelPropertiesSheet, onOk config: ChannelConfig) {
		if let index = model.config.channelList.firstIndex(where: { $0.uniqueIdentifier == config.uniqueIdentifier }) {
			model.config.channelList[index] = config
		} else {
			model.config.channelList.append(config)
		}
		model.selectedChannelID = config.uniqueIdentifier
	}

	private func addHighlight() {
		presentHighlightSheet(config: nil)
	}

	private func editHighlight() {
		guard let id = model.selectedHighlightID,
		      let entry = model.config.highlightList.first(where: { $0.uniqueIdentifier == id }) else { return }
		presentHighlightSheet(config: entry)
	}

	private func presentHighlightSheet(config: HighlightMatchCondition?) {
		let controller = HighlightEntrySheet(config: config, channels: model.config.channelList)
		controller.delegate = self
		controller.window = window
		controller.start()
		highlightSheet = controller
	}

	private func deleteHighlight() {
		guard let id = model.selectedHighlightID else { return }
		model.config.highlightList.removeAll { $0.uniqueIdentifier == id }
		model.selectedHighlightID = nil
	}

	func highlightEntrySheet(_: HighlightEntrySheet, didSave config: HighlightMatchCondition) {
		if let index = model.config.highlightList
			.firstIndex(where: { $0.uniqueIdentifier == config.uniqueIdentifier })
		{
			model.config.highlightList[index] = config
		} else {
			model.config.highlightList.append(config)
		}
		model.selectedHighlightID = config.uniqueIdentifier
	}

	private func addIgnoreAddressBookEntry(hostmask: String? = nil) {
		let controller = hostmask.map { AddressBookSheet(config: .newIgnoreEntry(forHostmask: $0)) }
			?? AddressBookSheet(entryType: .ignore)
		presentAddressBookSheet(controller)
	}

	private func addTrackingAddressBookEntry() {
		presentAddressBookSheet(AddressBookSheet(entryType: .userTracking))
	}

	private func editAddressBookEntry() {
		guard let id = model.selectedAddressBookEntryID,
		      let entry = model.config.ignoreList.first(where: { $0.uniqueIdentifier == id }) else { return }
		presentAddressBookSheet(AddressBookSheet(config: entry))
	}

	private func presentAddressBookSheet(_ controller: AddressBookSheet) {
		controller.delegate = self
		controller.window = window
		controller.start()
		addressBookSheet = controller
	}

	private func deleteAddressBookEntry() {
		guard let id = model.selectedAddressBookEntryID else { return }
		model.config.ignoreList.removeAll { $0.uniqueIdentifier == id }
		model.selectedAddressBookEntryID = nil
	}

	func addressBookSheet(_: AddressBookSheet, onOk entry: AddressBookEntry) {
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
	private func copyNickServCommand(for fingerprint: String) {
		guard model.config.identityClientSideCertificate != nil else { return }
		NSPasteboard.general.textualStringContent = "/msg NickServ cert add \(fingerprint)"
	}

	private func resetCertificate() {
		cancelCertificateSelection()
		model.config.identityClientSideCertificate = nil
	}

	private func chooseCertificate() {
		cancelCertificateSelection()
		certificateSelection.chooseIdentities { [weak self] identities in
			self?.presentCertificatePicker(identities)
		}
	}

	private func presentCertificatePicker(_ identities: [SecIdentity]) {
		guard !identities.isEmpty else {
			Alerts.alertSheet(
				body: ServerPropertiesStrings.Certificate.noneAvailableExplanation,
				title: ServerPropertiesStrings.Certificate.noneAvailableTitle,
				defaultButton: PromptStrings.Action.confirmation,
				alternateButton: nil,
				otherButton: nil
			)
			return
		}
		guard let panel = SFChooseIdentityPanel.shared() else { return }
		clientCertificatePanel = panel
		panel.setInformativeText(ServerPropertiesStrings.Certificate.chooseExplanation)
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
			message: ServerPropertiesStrings.Certificate.chooseTitle
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
		guard let client else { return }
		notifications.observe(.ClientConfigurationWasUpdated, object: client) { [weak self] notification in
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
		guard let client = notification.object as? Client else { return }
		Alerts.alertSheet(
			body: ServerPropertiesStrings.ExternalChange.unsavedChangesWarning,
			title: ServerPropertiesStrings.ExternalChange.reloadTitle,
			defaultButton: PromptStrings.Action.cancel,
			alternateButton: ServerPropertiesStrings.ExternalChange.reloadButton,
			otherButton: nil,
			destructiveButton: .alternate
		) { [weak self] outcome in
			guard outcome.response == .alternate, let self else { return }
			cancelCertificateSelection()
			client.updateStoredConfiguration()
			model.replace(with: client.config)
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
