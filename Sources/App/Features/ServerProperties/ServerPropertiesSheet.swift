/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import SecurityInterface

let serverPropertiesTableDragToken = NSPasteboard.PasteboardType(
	"com.vakesz.glasstual.server-properties.table-row"
)

enum ServerPropertiesSelection: UInt, CaseIterable {
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

/// What `ServerPropertiesSheet` reports back. The configuration is a value
/// type, so it cannot travel through `perform(_:with:with:)`.
@MainActor
public protocol ServerPropertiesSheetDelegate: AnyObject {
	func serverPropertiesSheet(_ sender: ServerPropertiesSheet, onOk config: ClientConfig)
	func serverPropertiesSheetWillClose(_ sender: ServerPropertiesSheet)
}

@objc(TDCServerPropertiesSheet)
@MainActor
public final class ServerPropertiesSheet: SheetBase, NSControlTextEditingDelegate, TDCClientPrototype {
	@objc public private(set) var client: IRCClient?
	@objc public private(set) var clientId: String?

	var config: ClientConfig
	let networkList = NetworkList()
	var encodingList: [String: NSNumber] = [:]
	var addressBookSheet: AddressBookSheet?
	var highlightSheet: HighlightEntrySheet?
	var channelSheet: ChannelPropertiesSheet?
	var serverEndpointSheet: ServerEndpointListSheet?
	weak var clientCertificateSelectCertificatePanel: SFChooseIdentityPanel?
	var populatingPrimaryServer = false
	var lastServerAddressValue: String?
	var previousPrimaryServer: Server?
	@objc private dynamic var floodControlDelayTimerSliderTempValue: UInt = 0
	@objc private dynamic var floodControlMessageCountSliderTempValue: UInt = 0

	@IBOutlet var addAddressBookEntryMenu: NSMenu!
	@IBOutlet var contentViewAddressBook: NSView!
	@IBOutlet var contentViewAutojoin: NSView!
	@IBOutlet var contentViewClientCertificate: NSView!
	@IBOutlet var contentViewConnectCommands: NSView!
	@IBOutlet var contentViewDisconnectMessages: NSView!
	@IBOutlet var contentViewEncoding: NSView!
	@IBOutlet var contentViewFloodControl: NSView!
	@IBOutlet var contentViewGeneral: NSView!
	@IBOutlet var contentViewHighlights: NSView!
	@IBOutlet var contentViewIdentity: NSView!
	@IBOutlet var contentViewNetworkSocket: NSView!
	@IBOutlet var contentViewProxyServer: NSView!
	@IBOutlet var contentViewProxyServerInputView: NSView!
	@IBOutlet var contentViewProxyServerSystemSocksView: NSView!
	@IBOutlet var contentViewProxyServerTorBrowserView: NSView!
	@IBOutlet var contentViewRedundancy: NSView!
	@IBOutlet var contentViewZncBouncer: NSView!

	@IBOutlet var addAddressBookEntryButton: NSButton!
	@IBOutlet var addChannelButton: NSButton!
	@IBOutlet var addHighlightButton: NSButton!
	@IBOutlet var autoConnectCheck: NSButton!
	@IBOutlet var autoDisconnectOnSleepCheck: NSButton!
	@IBOutlet var autoReconnectCheck: NSButton!
	@IBOutlet var autojoinWaitsForNickServCheck: NSButton!
	@IBOutlet var disconnectOnSASLFailureCheck: NSButton!
	@IBOutlet var clientCertificateChangeCertificateButton: NSButton!
	@IBOutlet var clientCertificateResetCertificateButton: NSButton!
	@IBOutlet var clientCertificateSHA1FingerprintCopyButton: NSButton!
	@IBOutlet var clientCertificateSHA2FingerprintCopyButton: NSButton!
	@IBOutlet var clientCertificateSHA512FingerprintCopyButton: NSButton!
	@IBOutlet var connectionIPv4AddressTypeCheck: NSButton!
	@IBOutlet var connectionIPv6AddressTypeCheck: NSButton!
	@IBOutlet var connectionDefaultAddressTypeCheck: NSButton!
	@IBOutlet var deleteAddressBookEntryButton: NSButton!
	@IBOutlet var deleteChannelButton: NSButton!
	@IBOutlet var deleteHighlightButton: NSButton!
	@IBOutlet var disconnectOnReachabilityChangeCheck: NSButton!
	@IBOutlet var editAddressBookEntryButton: NSButton!
	@IBOutlet var editChannelButton: NSButton!
	@IBOutlet var editHighlightButton: NSButton!
	@IBOutlet var hideAutojoinDelayedWarningsCheck: NSButton!
	@IBOutlet var performDisconnectOnPongTimerCheck: NSButton!
	@IBOutlet var pongTimerCheck: NSButton!
	@IBOutlet var prefersSecuredConnectionCheck: NSButton!
	@IBOutlet var setInvisibleModeOnConnectCheck: NSButton!
	@IBOutlet var runConnectCommandsSilentlyCheck: NSButton!
	@IBOutlet var validateServerCertificateChainCheck: NSButton!
	@IBOutlet var viewListOfPreferredCipherSuitesButton: NSButton!
	@IBOutlet var zncIgnoreConfiguredAutojoinCheck: NSButton!
	@IBOutlet var zncIgnorePlaybackNotificationsCheck: NSButton!
	@IBOutlet var zncOnlyPlaybackLatestCheck: NSButton!
	@IBOutlet var fallbackEncodingButton: NSPopUpButton!
	@IBOutlet var primaryEncodingButton: NSPopUpButton!
	@IBOutlet var preferredCipherSuitesButton: NSPopUpButton!
	@IBOutlet var proxyTypeButton: NSPopUpButton!
	@IBOutlet var floodControlDelayTimerSlider: NSSlider!
	@IBOutlet var floodControlMessageCountSlider: NSSlider!
	@IBOutlet var clientCertificateCommonNameField: NSTextField!
	@IBOutlet var clientCertificateSHA1FingerprintField: NSTextField!
	@IBOutlet var clientCertificateSHA2FingerprintField: NSTextField!
	@IBOutlet var clientCertificateSHA512FingerprintField: NSTextField!
	@IBOutlet var nicknamePasswordTextField: NSTextField!
	@IBOutlet var proxyPasswordTextField: NSTextField!
	@IBOutlet var proxyUsernameTextField: NSTextField!
	@IBOutlet var serverPasswordTextField: NSTextField!
	@IBOutlet var addressBookTable: BasicTableView!
	@IBOutlet var channelListTable: BasicTableView!
	@IBOutlet var highlightsTable: BasicTableView!
	@IBOutlet var serverAddressComboBox: ValidatedComboBox!
	@IBOutlet var navigationOutlineView: ContentNavigationOutlineView!
	@IBOutlet var alternateNicknamesTextField: ValidatedTextField!
	@IBOutlet var awayNicknameTextField: ValidatedTextField!
	@IBOutlet var ctcpVersionReplyTextField: ValidatedTextField!
	@IBOutlet var connectionNameTextField: ValidatedTextField!
	@IBOutlet var nicknameTextField: ValidatedTextField!
	@IBOutlet var normalLeavingCommentTextField: ValidatedTextField!
	@IBOutlet var proxyAddressTextField: ValidatedTextField!
	@IBOutlet var proxyPortTextField: ValidatedTextField!
	@IBOutlet var realNameTextField: ValidatedTextField!
	@IBOutlet var serverPortTextField: ValidatedTextField!
	@IBOutlet var sleepModeQuitMessageTextField: ValidatedTextField!
	@IBOutlet var usernameTextField: ValidatedTextField!
	@IBOutlet var connectCommandsField: NSTextView!
	/* The four lists the sheet edits. They used to live in `NSArrayController`s
	 that the nib bound to the tables; the tables read them through a diffable
	 data source now, so the sheet owns them outright. */
	var addressBookList: [AddressBookEntry] = []
	var channelList: [ChannelConfig] = []
	var highlightList: [HighlightMatchCondition] = []
	var serverList: [Server] = []

	var addressBookTableDataSource: ServerPropertiesTableDataSource?
	var channelListTableDataSource: ServerPropertiesTableDataSource?
	var highlightsTableDataSource: ServerPropertiesTableDataSource?

	@objc(initWithClient:)
	public init(client: IRCClient?) {
		self.client = client
		clientId = client?.uniqueIdentifier

		if let client {
			client.updateStoredConfiguration()
			config = client.config
		} else {
			config = ClientConfig()
		}

		super.init(window: nil)
		prepareInitialState()
		loadConfig()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCServerPropertiesSheet", owner: self, topLevelObjects: nil)
		sheet.preventsApplicationTerminationWhenModal = false
		sheet.autorecalculatesKeyViewLoop = true

		for network in networkList.listOfNetworks {
			serverAddressComboBox.addItem(withObjectValue: network.networkName)
		}

		connectCommandsField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
		connectCommandsField.textContainerInset = NSSize(width: 1, height: 3)
		configureValidatedFields()
		addConfigurationDidChangeObserver()
		configureTables()
		populateEncodings()
		populateTabViewList()
	}

	private func populateTabViewList() {
		func child(_ title: String, _ selection: ServerPropertiesSelection,
		           _ view: NSView) -> ContentNavigationOutlineViewItem
		{
			ContentNavigationOutlineViewItem(
				label: title,
				identifier: selection.rawValue,
				view: view,
				firstResponder: nil
			)
		}
		func group(
			_ title: String,
			_ children: [ContentNavigationOutlineViewItem]
		) -> ContentNavigationOutlineViewItem {
			ContentNavigationOutlineViewItem(
				label: title,
				identifier: 0,
				view: nil,
				firstResponder: nil,
				children: children
			)
		}

		let general = [
			child(ServerPropertiesStrings.Navigation.addressBook, .addressBook, contentViewAddressBook),
			child(ServerPropertiesStrings.Navigation.channelList, .autojoin, contentViewAutojoin),
			child(ServerPropertiesStrings.Navigation.connectCommands, .connectCommands, contentViewConnectCommands),
			child(ServerPropertiesStrings.Navigation.encoding, .encoding, contentViewEncoding),
			child(ServerPropertiesStrings.Navigation.general, .general, contentViewGeneral),
			child(ServerPropertiesStrings.Navigation.identity, .identity, contentViewIdentity),
			child(ServerPropertiesStrings.Navigation.highlights, .highlights, contentViewHighlights),
			child(
				ServerPropertiesStrings.Navigation.messages,
				.disconnectMessages,
				contentViewDisconnectMessages
			),
		]
		let vendor = [
			child(ServerPropertiesStrings.Navigation.zncBouncer, .zncBouncer, contentViewZncBouncer),
		]
		let advanced = [
			child(
				ServerPropertiesStrings.Navigation.clientCertificate,
				.clientCertificate,
				contentViewClientCertificate
			),
			child(ServerPropertiesStrings.Navigation.floodControl, .floodControl, contentViewFloodControl),
			child(ServerPropertiesStrings.Navigation.networkSocket, .networkSocket, contentViewNetworkSocket),
			child(ServerPropertiesStrings.Navigation.proxyServer, .proxyServer, contentViewProxyServer),
			child(ServerPropertiesStrings.Navigation.redundancy, .redundancy, contentViewRedundancy),
		]

		let tree = [
			group(ServerPropertiesStrings.Navigation.serverProperties, general),
			group(ServerPropertiesStrings.Navigation.vendorSpecific, vendor),
			group(ServerPropertiesStrings.Navigation.advanced, advanced),
		]
		navigationOutlineView.navigationTreeMatrix = tree
		navigationOutlineView.contentViewPreferredWidth = 100
		navigationOutlineView.contentViewPreferredHeight = 100
		navigationOutlineView.expandParentOnDoubleClick = true
		navigationOutlineView.expandItem(tree[0])
	}

	@objc public func start() {
		start(withSelection: ServerPropertiesSelection.default.rawValue, context: nil)
	}

	@objc(startWithSelection:context:)
	public func start(withSelection selectionValue: UInt, context: Any?) {
		startSheet()
		let selection = ServerPropertiesSelection(rawValue: selectionValue) ?? .default
		navigate(to: selection)
		if selection == .newIgnoreEntry {
			if let hostmask = context as? String {
				addIgnoreAddressBookEntry(withHostmask: hostmask)
			} else if let entry = context as? AddressBookEntry {
				editAddressBookEntry(with: entry)
			}
		}
	}

	func navigate(to requestedSelection: ServerPropertiesSelection) {
		let selection: ServerPropertiesSelection = switch requestedSelection {
		case .default: .general
		case .newIgnoreEntry: .addressBook
		default: requestedSelection
		}
		navigationOutlineView.navigateToItem(withIdentifier: selection.rawValue)
		sheet.recalculateKeyViewLoop()
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
		} else if let panel = clientCertificateSelectCertificatePanel {
			panel.sheetParent?.endSheet(
				panel,
				returnCode: .cancel
			)
		}
	}

	@IBAction override public func ok(_ sender: Any?) {
		guard okOrError() else { return }
		removeConfigurationDidChangeObserver()
		closeChildSheets()
		saveConfig()
		(delegate as? any ServerPropertiesSheetDelegate)?.serverPropertiesSheet(self, onOk: config)
		super.ok(sender)
	}

	@IBAction override public func cancel(_ sender: Any?) {
		removeConfigurationDidChangeObserver()
		closeChildSheets()
		super.cancel(sender)
	}

	private func addConfigurationDidChangeObserver() {
		guard let client else { return }
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(underlyingConfigurationChanged(_:)),
			name: .IRCClientConfigurationWasUpdated,
			object: client
		)
	}

	private func removeConfigurationDidChangeObserver() {
		NotificationCenter.default.removeObserver(self, name: .IRCClientConfigurationWasUpdated, object: nil)
	}

	@objc private func underlyingConfigurationChanged(_ notification: Notification) {
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
			close()
			client.updateStoredConfiguration()
			config = client.config
			loadConfig()
			start()
		}
	}

	private func loadConfig() {
		connectionNameTextField.stringValue = config.connectionName
		autoConnectCheck.state = config.autoConnect ? .on : .off
		autoReconnectCheck.state = config.autoReconnect ? .on : .off
		autoDisconnectOnSleepCheck.state = config.autoSleepModeDisconnect ? .on : .off
		zncIgnoreConfiguredAutojoinCheck.state = config.zncIgnoreConfiguredAutojoin ? .on : .off
		zncIgnorePlaybackNotificationsCheck.state = config.zncIgnorePlaybackNotifications ? .on : .off
		zncOnlyPlaybackLatestCheck.state = config.zncOnlyPlaybackLatest ? .on : .off

		connectionIPv4AddressTypeCheck.state = config.addressType == .v4 ? .on : .off
		connectionIPv6AddressTypeCheck.state = config.addressType == .v6 ? .on : .off
		connectionDefaultAddressTypeCheck.state = config.addressType == .default ? .on : .off
		pongTimerCheck.state = config.performPongTimer ? .on : .off
		performDisconnectOnPongTimerCheck.state = config.performDisconnectOnPongTimer ? .on : .off
		disconnectOnReachabilityChangeCheck.state = config.performDisconnectOnReachabilityChange ? .on : .off
		validateServerCertificateChainCheck.state = config.validateServerCertificateChain ? .on : .off
		preferredCipherSuitesButton.selectItem(withTag: Int(config.cipherSuites.rawValue))

		nicknameTextField.stringValue = config.nickname.isEmpty ? TextualPreferences.defaultNickname() : config.nickname
		awayNicknameTextField.stringValue = config.awayNickname ?? ""
		alternateNicknamesTextField.stringValue = config.alternateNicknames.joined(separator: " ")
		usernameTextField.stringValue = config.username.isEmpty ? TextualPreferences.defaultUsername() : config.username
		ctcpVersionReplyTextField.stringValue = config.ctcpVersionReply ?? ""
		realNameTextField.stringValue = config.realName.isEmpty ? TextualPreferences.defaultRealName() : config.realName
		nicknamePasswordTextField.stringValue = config.nicknamePassword ?? ""
		autojoinWaitsForNickServCheck.state = config.autojoinWaitsForNickServ ? .on : .off
		disconnectOnSASLFailureCheck.state = config.disconnectOnSASLFailure ? .on : .off
		hideAutojoinDelayedWarningsCheck.state = config.hideAutojoinDelayedWarnings ? .off : .on

		normalLeavingCommentTextField.stringValue = config.normalLeavingComment
		sleepModeQuitMessageTextField.stringValue = config.sleepModeLeavingComment

		selectEncoding(config.primaryEncoding, in: primaryEncodingButton)
		selectEncoding(config.fallbackEncoding, in: fallbackEncodingButton)

		proxyTypeButton.selectItem(withTag: Int(config.proxyType.rawValue))
		proxyAddressTextField.stringValue = config.proxyAddress ?? ""
		proxyPortTextField.integerValue = Int(config.proxyPort)
		proxyUsernameTextField.stringValue = config.proxyUsername ?? ""
		proxyPasswordTextField.stringValue = config.proxyPassword ?? ""

		connectCommandsField.string = config.loginCommands.joined(separator: "\n")
		setInvisibleModeOnConnectCheck.state = config.setInvisibleModeOnConnect ? .on : .off
		runConnectCommandsSilentlyCheck.state = config.runConnectCommandsSilently ? .on : .off
		floodControlDelayTimerSliderTempValue = config.floodControlDelayTimerInterval
		floodControlMessageCountSliderTempValue = config.floodControlMaximumMessages

		addressBookList = config.ignoreList
		channelList = config.channelList
		highlightList = config.highlightList
		serverList = config.serverList

		applyAddressBookList()
		applyChannelList()
		applyHighlightList()

		loadPrimaryServerEndpoint()
		updateAddressBookPage()
		updateChannelListPage()
		updateClientCertificatePage()
		updateHighlightsPage()
		updateIdentityPage()
		preferredCipherSuitesChanged(nil)
		proxyTypeChanged(nil)
	}

	private func saveConfig() {
		config.connectionName = connectionNameTextField.value
		config.autoConnect = autoConnectCheck.state == .on
		config.autoReconnect = autoReconnectCheck.state == .on
		config.autoSleepModeDisconnect = autoDisconnectOnSleepCheck.state == .on
		config.zncIgnoreConfiguredAutojoin = zncIgnoreConfiguredAutojoinCheck.state == .on
		config.zncIgnorePlaybackNotifications = zncIgnorePlaybackNotificationsCheck.state == .on
		config.zncOnlyPlaybackLatest = zncOnlyPlaybackLatestCheck.state == .on
		config.performPongTimer = pongTimerCheck.state == .on
		config.performDisconnectOnPongTimer = performDisconnectOnPongTimerCheck.state == .on
		config.performDisconnectOnReachabilityChange = disconnectOnReachabilityChangeCheck.state == .on
		config.validateServerCertificateChain = validateServerCertificateChainCheck.state == .on
		config
			.cipherSuites = CipherSuiteCollection(rawValue: UInt(preferredCipherSuitesButton.selectedTag())) ??
			.default

		config.nickname = nicknameTextField.value
		config.username = usernameTextField.value
		config.realName = realNameTextField.value
		let versionReply = ctcpVersionReplyTextField.value
		config.ctcpVersionReply = versionReply.isEmpty ? nil : versionReply
		config.awayNickname = Self.nilIfEmpty(awayNicknameTextField.value)
		config.nicknamePassword = Self.nilIfEmpty(
			nicknamePasswordTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		)
		config.autojoinWaitsForNickServ = autojoinWaitsForNickServCheck.state == .on
		config.disconnectOnSASLFailure = disconnectOnSASLFailureCheck.state == .on
		config.hideAutojoinDelayedWarnings = hideAutojoinDelayedWarningsCheck.state != .on
		config.alternateNicknames = uniqueNonempty(
			alternateNicknamesTextField.value.components(separatedBy: .whitespaces)
		)

		config.sleepModeLeavingComment = sleepModeQuitMessageTextField.value
		config.normalLeavingComment = normalLeavingCommentTextField.value
		config.primaryEncoding = Self.encoding(forTag: primaryEncodingButton.selectedTag(), default: .utf8)
		config.fallbackEncoding = Self.encoding(forTag: fallbackEncodingButton.selectedTag(), default: .isoLatin1)

		config.proxyType = Self.proxyType(forTag: proxyTypeButton.selectedTag())
		config.proxyAddress = Self.nilIfEmpty(proxyAddressTextField.lowercaseValue)
		config.proxyPort = UInt16(clamping: proxyPortTextField.integerValue)
		config.proxyUsername = Self.nilIfEmpty(
			proxyUsernameTextField.stringValue.firstToken
		)
		config.proxyPassword = Self.nilIfEmpty(
			proxyPasswordTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		)
		config.loginCommands = connectCommandsField.string
			.components(separatedBy: .newlines)
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
		config.setInvisibleModeOnConnect = setInvisibleModeOnConnectCheck.state == .on
		config.runConnectCommandsSilently = runConnectCommandsSilentlyCheck.state == .on
		config.floodControlMaximumMessages = floodControlMessageCountSliderTempValue
		config.floodControlDelayTimerInterval = floodControlDelayTimerSliderTempValue
		config.channelList = channelList
		config.highlightList = highlightList
		config.ignoreList = addressBookList
		config.serverList = serverList
	}

	/// `dictionaryValue(for:)` omits a nil but persists an empty string, so
	/// every optional field has to normalise the same way.
	static func nilIfEmpty(_ value: String) -> String? {
		value.isEmpty ? nil : value
	}

	/// One fallback, shared by the sheet, its validators and saveConfig, which
	/// used to disagree about what an unrecognised tag meant.
	static func proxyType(forTag tag: Int) -> IRCConnectionProxyType {
		guard tag >= 0, let type = IRCConnectionProxyType(rawValue: UInt(tag)) else {
			return .none
		}

		return type
	}

	static func proxyTypeUsesAddress(_ tag: Int) -> Bool {
		[.socks5, .HTTP].contains(proxyType(forTag: tag))
	}

	static func encoding(forTag tag: Int, default fallback: String.Encoding) -> UInt {
		tag > 0 ? UInt(tag) : fallback.rawValue
	}

	private func uniqueNonempty(_ values: [String]) -> [String] {
		var seen = Set<String>()
		return values.filter { !$0.isEmpty && seen.insert($0).inserted }
	}

	@objc public func windowWillClose(_: Notification) {
		removeConfigurationDidChangeObserver()
		for table in [addressBookTable, channelListTable, highlightsTable] {
			table?.delegate = nil
			table?.dataSource = nil
			table?.unregisterDraggedTypes()
		}
		sheet.makeFirstResponder(nil)
		(delegate as? any ServerPropertiesSheetDelegate)?.serverPropertiesSheetWillClose(self)
	}
}
