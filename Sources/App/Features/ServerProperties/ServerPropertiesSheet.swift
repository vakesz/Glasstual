/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import GlasstualPluginKit
import Security
import SecurityInterface
import SwiftUI

enum ServerPropertiesSelection: UInt, CaseIterable, Hashable {
	case `default` = 0
	case addressBook = 1
	case autojoin = 2
	case connectCommands = 3
	case encoding = 4
	case general = 5
	case identity = 6
	case highlights = 7
	case disconnectMessages = 8
	case zncBouncer = 10
	case clientCertificate = 12
	case floodControl = 13
	case networkSocket = 14
	case proxyServer = 15
	case redundancy = 16
	case newIgnoreEntry = 200
}

func serverPropertiesModel<Model>(_ value: Any, as _: Model.Type) -> Model {
	guard let model = value as? Model else {
		preconditionFailure("Expected a \(Model.self) copy, received \(Swift.type(of: value))")
	}
	return model
}

@MainActor
public protocol ServerPropertiesSheetDelegate: AnyObject {
	func serverPropertiesSheet(_ sender: ServerPropertiesSheet, onOk config: ClientConfig)
	func serverPropertiesSheetWillClose(_ sender: ServerPropertiesSheet)
}

@objc(TDCServerPropertiesSheet)
@MainActor
public final class ServerPropertiesSheet: SheetBase, NSWindowDelegate, TDCClientPrototype,
	AddressBookSheetDelegate, ChannelPropertiesSheetDelegate, HighlightEntrySheetDelegate,
	ServerEndpointListSheetDelegate
{
	private static let contentSize = NSSize(width: 900, height: 650)

	public private(set) var client: IRCClient?
	public private(set) var clientId: String?
	let model: ServerPropertiesModel

	private let notifications = NotificationSubscriptions()
	private var addressBookSheet: AddressBookSheet?
	private var channelSheet: ChannelPropertiesSheet?
	private var highlightSheet: HighlightEntrySheet?
	private var serverEndpointSheet: ServerEndpointListSheet?
	private weak var clientCertificatePanel: SFChooseIdentityPanel?

	var config: ClientConfig {
		get { model.config }
		set {
			model.replace(with: newValue)
			updateClientCertificateDetails()
		}
	}

	public init(client: IRCClient?) {
		self.client = client
		clientId = client?.uniqueIdentifier
		if let client {
			client.updateStoredConfiguration()
			model = ServerPropertiesModel(config: client.config)
		} else {
			model = ServerPropertiesModel(config: ClientConfig())
		}
		super.init(window: nil)
		installSheet()
		addConfigurationDidChangeObserver()
		updateClientCertificateDetails()
	}

	private func installSheet() {
		let actions = ServerPropertiesActions(
			submit: { [weak self] in self?.ok(nil) },
			cancel: { [weak self] in self?.cancel(nil) },
			editEndpoints: { [weak self] in self?.editServerEndpoints() },
			addChannel: { [weak self] in self?.addChannel() },
			editChannel: { [weak self] in self?.editChannel() },
			deleteChannel: { [weak self] in self?.deleteChannel() },
			addHighlight: { [weak self] in self?.addHighlight() },
			editHighlight: { [weak self] in self?.editHighlight() },
			deleteHighlight: { [weak self] in self?.deleteHighlight() },
			addIgnore: { [weak self] in self?.addIgnoreAddressBookEntry(hostmask: nil) },
			addTracking: { [weak self] in self?.addTrackingAddressBookEntry() },
			editAddressBookEntry: { [weak self] in self?.editAddressBookEntry() },
			deleteAddressBookEntry: { [weak self] in self?.deleteAddressBookEntry() },
			chooseCertificate: { [weak self] in self?.chooseCertificate() },
			resetCertificate: { [weak self] in self?.resetCertificate() },
			copyCertificateFingerprint: { [weak self] value in self?.copyCertificateFingerprint(value) },
			showCipherSuites: { [weak self] in self?.showCipherSuites() },
			openProxySettings: { PreferencesController.openProxySettingsInSystemPreferences() }
		)
		let hostedSheet = NSWindow(
			contentRect: NSRect(origin: .zero, size: Self.contentSize),
			styleMask: [.titled, .resizable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		hostedSheet.contentViewController = NSHostingController(
			rootView: ServerPropertiesView(model: model, actions: actions)
		)
		hostedSheet.contentMinSize = NSSize(width: 760, height: 520)
		hostedSheet.delegate = self
		hostedSheet.isReleasedWhenClosed = false
		hostedSheet.isRestorable = false
		hostedSheet.preventsApplicationTerminationWhenModal = false
		hostedSheet.tabbingMode = .disallowed
		hostedSheet.title = ServerPropertiesStrings.Navigation.serverProperties
		sheet = hostedSheet
	}

	public func start() {
		start(withSelection: ServerPropertiesSelection.default.rawValue, context: nil)
	}

	public func start(withSelection selectionValue: UInt, context: Any?) {
		let requested = ServerPropertiesSelection(rawValue: selectionValue) ?? .default
		model.selection = switch requested {
		case .default: .general
		case .newIgnoreEntry: .addressBook
		default: requested
		}
		startSheet()
		if requested == .newIgnoreEntry {
			if let hostmask = context as? String {
				addIgnoreAddressBookEntry(hostmask: hostmask)
			} else if let entry = context as? AddressBookEntry {
				editAddressBookEntry(with: entry)
			}
		}
	}

	override public func ok(_ sender: Any?) {
		guard let submitted = model.submittedConfig() else { return }
		model.config = submitted
		removeConfigurationDidChangeObserver()
		closeChildSheets()
		(delegate as? any ServerPropertiesSheetDelegate)?.serverPropertiesSheet(self, onOk: submitted)
		super.ok(sender)
	}

	override public func cancel(_ sender: Any?) {
		removeConfigurationDidChangeObserver()
		closeChildSheets()
		super.cancel(sender)
	}

	private func editServerEndpoints() {
		let controller = ServerEndpointListSheet(window: sheet)
		controller.delegate = self
		controller.start(with: model.config.serverList)
		serverEndpointSheet = controller
	}

	public func serverEndpointListSheet(_: ServerEndpointListSheet, onOk serverList: [Server]) {
		model.config.serverList = serverList
		model.replace(with: model.config)
	}

	public func serverEndpointListSheetWillClose(_: ServerEndpointListSheet) {
		serverEndpointSheet = nil
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
		let controller = ChannelPropertiesSheet(config: config)
		controller.delegate = self
		controller.window = sheet
		controller.start()
		channelSheet = controller
	}

	private func deleteChannel() {
		guard let id = model.selectedChannelID else { return }
		model.config.channelList.removeAll { $0.uniqueIdentifier == id }
		model.selectedChannelID = nil
	}

	public func channelPropertiesSheet(_: ChannelPropertiesSheet, onOk config: ChannelConfig) {
		if let index = model.config.channelList.firstIndex(where: { $0.uniqueIdentifier == config.uniqueIdentifier }) {
			model.config.channelList[index] = config
		} else {
			model.config.channelList.append(config)
		}
		model.selectedChannelID = config.uniqueIdentifier
	}

	public func channelPropertiesSheetWillClose(_: ChannelPropertiesSheet) {
		channelSheet = nil
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
		controller.window = sheet
		controller.start()
		highlightSheet = controller
	}

	private func deleteHighlight() {
		guard let id = model.selectedHighlightID else { return }
		model.config.highlightList.removeAll { $0.uniqueIdentifier == id }
		model.selectedHighlightID = nil
	}

	public func highlightEntrySheet(_: HighlightEntrySheet, didSave config: HighlightMatchCondition) {
		if let index = model.config.highlightList
			.firstIndex(where: { $0.uniqueIdentifier == config.uniqueIdentifier })
		{
			model.config.highlightList[index] = config
		} else {
			model.config.highlightList.append(config)
		}
		model.selectedHighlightID = config.uniqueIdentifier
	}

	public func highlightEntrySheetDidClose(_: HighlightEntrySheet) {
		highlightSheet = nil
	}

	func addIgnoreAddressBookEntry(withHostmask hostmask: String? = nil) {
		addIgnoreAddressBookEntry(hostmask: hostmask)
	}

	private func addIgnoreAddressBookEntry(hostmask: String? = nil) {
		let controller = hostmask.map { AddressBookSheet(config: .newIgnoreEntry(forHostmask: $0)) }
			?? AddressBookSheet(entryType: .ignore)
		presentAddressBookSheet(controller)
	}

	private func addTrackingAddressBookEntry() {
		presentAddressBookSheet(AddressBookSheet(entryType: .userTracking))
	}

	func editAddressBookEntry(with entry: AddressBookEntry) {
		model.selectedAddressBookEntryID = entry.uniqueIdentifier
		editAddressBookEntry()
	}

	private func editAddressBookEntry() {
		guard let id = model.selectedAddressBookEntryID,
		      let entry = model.config.ignoreList.first(where: { $0.uniqueIdentifier == id }) else { return }
		presentAddressBookSheet(AddressBookSheet(config: entry))
	}

	private func presentAddressBookSheet(_ controller: AddressBookSheet) {
		controller.delegate = self
		controller.window = sheet
		controller.start()
		addressBookSheet = controller
	}

	private func deleteAddressBookEntry() {
		guard let id = model.selectedAddressBookEntryID else { return }
		model.config.ignoreList.removeAll { $0.uniqueIdentifier == id }
		model.selectedAddressBookEntryID = nil
	}

	public func addressBookSheet(_: AddressBookSheet, onOk entry: AddressBookEntry) {
		if let index = model.config.ignoreList.firstIndex(where: { $0.uniqueIdentifier == entry.uniqueIdentifier }) {
			model.config.ignoreList[index] = entry
		} else {
			model.config.ignoreList.append(entry)
		}
		model.selectedAddressBookEntryID = entry.uniqueIdentifier
	}

	public func addressBookSheetWillClose(_: AddressBookSheet) {
		addressBookSheet = nil
	}

	private struct CertificateDetails {
		let commonName: String
		let sha512: String
		let sha256: String
		let sha1: String
	}

	private func certificateDetails() -> CertificateDetails? {
		guard let reference = model.config.identityClientSideCertificate else { return nil }
		let query: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValuePersistentRef: reference,
		                              kSecReturnRef: true]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      let result, CFGetTypeID(result) == SecCertificateGetTypeID() else { return nil }
		let certificate = unsafeDowncast(result, to: SecCertificate.self)
		var commonNameReference: CFString?
		guard SecCertificateCopyCommonName(certificate, &commonNameReference) == errSecSuccess,
		      let commonName = commonNameReference as String? else { return nil }
		let data = SecCertificateCopyData(certificate) as Data
		return CertificateDetails(
			commonName: commonName,
			sha512: (data as NSData).textualSha512.uppercased(),
			sha256: (data as NSData).textualSha256.uppercased(),
			sha1: (data as NSData).textualSha1.uppercased()
		)
	}

	private func updateClientCertificateDetails() {
		let details = certificateDetails()
		let empty = ServerPropertiesStrings.Certificate.noneSelected
		model.certificateName = details?.commonName ?? empty
		model.certificateSHA512 = details?.sha512 ?? empty
		model.certificateSHA256 = details?.sha256 ?? empty
		model.certificateSHA1 = details?.sha1 ?? empty
	}

	private func copyCertificateFingerprint(_ fingerprint: String) {
		guard model.config.identityClientSideCertificate != nil else { return }
		NSPasteboard.general.textualStringContent = "/msg NickServ cert add \(fingerprint)"
	}

	private func resetCertificate() {
		model.config.identityClientSideCertificate = nil
		updateClientCertificateDetails()
	}

	private func chooseCertificate() {
		let query: [CFString: Any] = [kSecClass: kSecClassIdentity, kSecMatchLimit: kSecMatchLimitAll,
		                              kSecReturnRef: true]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      let identities = result as? [SecIdentity], !identities.isEmpty
		else {
			TDCAlert.alert(
				withMessage: ServerPropertiesStrings.Certificate.noneAvailableExplanation,
				title: ServerPropertiesStrings.Certificate.noneAvailableTitle,
				defaultButton: PromptStrings.Action.confirmation,
				alternateButton: nil
			)
			return
		}
		guard let panel = SFChooseIdentityPanel.shared() else { return }
		clientCertificatePanel = panel
		panel.setInformativeText(ServerPropertiesStrings.Certificate.chooseExplanation)
		panel.setAlternateButtonTitle(PromptStrings.Action.cancel)
		panel.beginSheet(
			for: sheet,
			modalDelegate: self,
			didEnd: #selector(identityPanelDidEnd(_:returnCode:contextInfo:)),
			contextInfo: nil,
			identities: identities,
			message: ServerPropertiesStrings.Certificate.chooseTitle
		)
	}

	@objc private func identityPanelDidEnd(
		_ panel: SFChooseIdentityPanel,
		returnCode: Int,
		contextInfo _: UnsafeMutableRawPointer?
	) {
		defer { clientCertificatePanel = nil }
		guard returnCode == NSApplication.ModalResponse.OK.rawValue,
		      let identity = panel.identity()?.takeUnretainedValue() else { return }
		var certificate: SecCertificate?
		guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { return }
		let query: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValueRef: certificate,
		                              kSecReturnPersistentRef: true]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      let reference = result as? Data else { return }
		model.config.identityClientSideCertificate = reference
		model.primaryServerIsSecured = true
		updateClientCertificateDetails()
	}

	private func showCipherSuites() {
		let descriptions = SecureTransportSupport.descriptions(
			forCipherListCollection: model.config.cipherSuites,
			withProtocol: true
		)
		TDCAlert.alertSheet(
			with: sheet,
			body: ServerPropertiesStrings.CipherSuites.description(descriptions.joined(separator: "\n")),
			title: ServerPropertiesStrings.CipherSuites.title(collectionName: ""),
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil,
			otherButton: nil
		)
	}

	private func addConfigurationDidChangeObserver() {
		guard let client else { return }
		notifications.observe(.IRCClientConfigurationWasUpdated, object: client) { [weak self] notification in
			self?.underlyingConfigurationChanged(notification)
		}
	}

	private func removeConfigurationDidChangeObserver() {
		notifications.cancelAll()
	}

	private func underlyingConfigurationChanged(_ notification: Notification) {
		guard let client = notification.object as? IRCClient else { return }
		TDCAlert.alertSheet(
			with: sheet.ceDeepestWindow,
			body: ServerPropertiesStrings.ExternalChange.unsavedChangesWarning,
			title: ServerPropertiesStrings.ExternalChange.reloadTitle,
			defaultButton: PromptStrings.Action.yes,
			alternateButton: PromptStrings.Action.no,
			otherButton: nil
		) { [weak self] outcome in
			guard outcome.response == .default, let self else { return }
			client.updateStoredConfiguration()
			model.replace(with: client.config)
			updateClientCertificateDetails()
		}
	}

	private func closeChildSheets() {
		if let addressBookSheet {
			addressBookSheet.close()
		} else if let channelSheet {
			channelSheet.close()
		} else if let highlightSheet {
			highlightSheet.close()
		} else if let serverEndpointSheet {
			serverEndpointSheet.close()
		} else if let panel = clientCertificatePanel {
			panel.sheetParent?.endSheet(panel, returnCode: .cancel)
		}
	}

	public func windowWillClose(_: Notification) {
		removeConfigurationDidChangeObserver()
		(delegate as? any ServerPropertiesSheetDelegate)?.serverPropertiesSheetWillClose(self)
	}

	static func displayedChannels(in channelList: [ChannelConfig]) -> [ChannelConfig] {
		channelList.filter { $0.type == .channel }
	}

	static func nilIfEmpty(_ value: String) -> String? {
		ServerPropertiesModel.nilIfEmpty(value)
	}

	static func proxyType(forTag tag: Int) -> IRCConnectionProxyType {
		ServerPropertiesModel.proxyType(forTag: tag)
	}

	static func proxyTypeUsesAddress(_ tag: Int) -> Bool {
		ServerPropertiesModel.proxyTypeUsesAddress(ServerPropertiesModel.proxyType(forTag: tag))
	}

	static func encoding(forTag tag: Int, default fallback: String.Encoding) -> UInt {
		ServerPropertiesModel.encoding(forTag: tag, default: fallback)
	}
}
