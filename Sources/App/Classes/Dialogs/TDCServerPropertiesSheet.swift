/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import Security
import SecurityInterface

private let serverPropertiesTableDragToken = NSPasteboard.PasteboardType(
	"com.vakesz.glasstual.server-properties.table-row"
)

private enum ServerPropertiesSelection: UInt, CaseIterable {
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

enum ServerPropertiesValidation {
	static func isNickname(_ value: String) -> Bool {
		(value as NSString).isHostmaskNickname
	}

	static func isUsername(_ value: String) -> Bool {
		(value as NSString).isHostmaskUsername
	}

	static func isInternetAddress(_ value: String) -> Bool {
		(value as NSString).isValidInternetAddress
	}

	static func isInternetPort(_ value: String) -> Bool {
		(value as NSString).isValidInternetPort
	}

	static func isSingleLine(_ value: String) -> Bool {
		value.rangeOfCharacter(from: .newlines) == nil
	}

	static func isLeavingComment(_ value: String) -> Bool {
		isSingleLine(value) && value.count <= 390
	}

	static func areAlternateNicknamesValid(_ value: String) -> Bool {
		value.components(separatedBy: .whitespaces).allSatisfy(isNickname)
	}
}

@objc(TDCServerPropertiesSheet)
@MainActor
public final class ServerPropertiesSheet: SheetBase, NSControlTextEditingDelegate {
	@objc public private(set) var client: IRCClient?
	@objc public private(set) var clientId: String?

	private var config: MutableClientConfig
	private let networkList = NetworkList()
	private var encodingList: [String: NSNumber] = [:]
	private var addressBookSheet: AddressBookSheet?
	private var highlightSheet: HighlightEntrySheet?
	private var channelSheet: ChannelPropertiesSheet?
	private var serverEndpointSheet: ServerEndpointListSheet?
	private weak var clientCertificateSelectCertificatePanel: SFChooseIdentityPanel?
	private var populatingPrimaryServer = false
	private var lastServerAddressValue: String?
	private var previousPrimaryServer: Server?
	@objc private dynamic var floodControlDelayTimerSliderTempValue: UInt = 0
	@objc private dynamic var floodControlMessageCountSliderTempValue: UInt = 0

	@IBOutlet private var addAddressBookEntryMenu: NSMenu!
	@IBOutlet private var contentViewAddressBook: NSView!
	@IBOutlet private var contentViewAutojoin: NSView!
	@IBOutlet private var contentViewClientCertificate: NSView!
	@IBOutlet private var contentViewConnectCommands: NSView!
	@IBOutlet private var contentViewDisconnectMessages: NSView!
	@IBOutlet private var contentViewEncoding: NSView!
	@IBOutlet private var contentViewFloodControl: NSView!
	@IBOutlet private var contentViewGeneral: NSView!
	@IBOutlet private var contentViewHighlights: NSView!
	@IBOutlet private var contentViewIdentity: NSView!
	@IBOutlet private var contentViewNetworkSocket: NSView!
	@IBOutlet private var contentViewProxyServer: NSView!
	@IBOutlet private var contentViewProxyServerInputView: NSView!
	@IBOutlet private var contentViewProxyServerSystemSocksView: NSView!
	@IBOutlet private var contentViewProxyServerTorBrowserView: NSView!
	@IBOutlet private var contentViewRedundancy: NSView!
	@IBOutlet private var contentViewZncBouncer: NSView!

	@IBOutlet private var addAddressBookEntryButton: NSButton!
	@IBOutlet private var addChannelButton: NSButton!
	@IBOutlet private var addHighlightButton: NSButton!
	@IBOutlet private var autoConnectCheck: NSButton!
	@IBOutlet private var autoDisconnectOnSleepCheck: NSButton!
	@IBOutlet private var autoReconnectCheck: NSButton!
	@IBOutlet private var autojoinWaitsForNickServCheck: NSButton!
	@IBOutlet private var clientCertificateChangeCertificateButton: NSButton!
	@IBOutlet private var clientCertificateResetCertificateButton: NSButton!
	@IBOutlet private var clientCertificateSHA1FingerprintCopyButton: NSButton!
	@IBOutlet private var clientCertificateSHA2FingerprintCopyButton: NSButton!
	@IBOutlet private var clientCertificateSHA512FingerprintCopyButton: NSButton!
	@IBOutlet private var connectionIPv4AddressTypeCheck: NSButton!
	@IBOutlet private var connectionIPv6AddressTypeCheck: NSButton!
	@IBOutlet private var connectionDefaultAddressTypeCheck: NSButton!
	@IBOutlet private var deleteAddressBookEntryButton: NSButton!
	@IBOutlet private var deleteChannelButton: NSButton!
	@IBOutlet private var deleteHighlightButton: NSButton!
	@IBOutlet private var disconnectOnReachabilityChangeCheck: NSButton!
	@IBOutlet private var editAddressBookEntryButton: NSButton!
	@IBOutlet private var editChannelButton: NSButton!
	@IBOutlet private var editHighlightButton: NSButton!
	@IBOutlet private var hideAutojoinDelayedWarningsCheck: NSButton!
	@IBOutlet private var performDisconnectOnPongTimerCheck: NSButton!
	@IBOutlet private var pongTimerCheck: NSButton!
	@IBOutlet private var prefersSecuredConnectionCheck: NSButton!
	@IBOutlet private var setInvisibleModeOnConnectCheck: NSButton!
	@IBOutlet private var runConnectCommandsSilentlyCheck: NSButton!
	@IBOutlet private var validateServerCertificateChainCheck: NSButton!
	@IBOutlet private var viewListOfPreferredCipherSuitesButton: NSButton!
	@IBOutlet private var zncIgnoreConfiguredAutojoinCheck: NSButton!
	@IBOutlet private var zncIgnorePlaybackNotificationsCheck: NSButton!
	@IBOutlet private var zncOnlyPlaybackLatestCheck: NSButton!
	@IBOutlet private var fallbackEncodingButton: NSPopUpButton!
	@IBOutlet private var primaryEncodingButton: NSPopUpButton!
	@IBOutlet private var preferredCipherSuitesButton: NSPopUpButton!
	@IBOutlet private var proxyTypeButton: NSPopUpButton!
	@IBOutlet private var floodControlDelayTimerSlider: NSSlider!
	@IBOutlet private var floodControlMessageCountSlider: NSSlider!
	@IBOutlet private var clientCertificateCommonNameField: NSTextField!
	@IBOutlet private var clientCertificateSHA1FingerprintField: NSTextField!
	@IBOutlet private var clientCertificateSHA2FingerprintField: NSTextField!
	@IBOutlet private var clientCertificateSHA512FingerprintField: NSTextField!
	@IBOutlet private var nicknamePasswordTextField: NSTextField!
	@IBOutlet private var proxyPasswordTextField: NSTextField!
	@IBOutlet private var proxyUsernameTextField: NSTextField!
	@IBOutlet private var serverPasswordTextField: NSTextField!
	@IBOutlet private var addressBookTable: BasicTableView!
	@IBOutlet private var channelListTable: BasicTableView!
	@IBOutlet private var highlightsTable: BasicTableView!
	@IBOutlet private var serverAddressComboBox: ValidatedComboBox!
	@IBOutlet private var navigationOutlineView: ContentNavigationOutlineView!
	@IBOutlet private var alternateNicknamesTextField: ValidatedTextField!
	@IBOutlet private var awayNicknameTextField: ValidatedTextField!
	@IBOutlet private var ctcpVersionReplyTextField: ValidatedTextField!
	@IBOutlet private var connectionNameTextField: ValidatedTextField!
	@IBOutlet private var nicknameTextField: ValidatedTextField!
	@IBOutlet private var normalLeavingCommentTextField: ValidatedTextField!
	@IBOutlet private var proxyAddressTextField: ValidatedTextField!
	@IBOutlet private var proxyPortTextField: ValidatedTextField!
	@IBOutlet private var realNameTextField: ValidatedTextField!
	@IBOutlet private var serverPortTextField: ValidatedTextField!
	@IBOutlet private var sleepModeQuitMessageTextField: ValidatedTextField!
	@IBOutlet private var usernameTextField: ValidatedTextField!
	@IBOutlet private var connectCommandsField: NSTextView!
	@IBOutlet private var addressBookArrayController: NSArrayController!
	@IBOutlet private var channelListArrayController: NSArrayController!
	@IBOutlet private var highlightListArrayController: NSArrayController!
	@IBOutlet private var serverListArrayController: NSArrayController!

	@objc(initWithClient:)
	public init(client: IRCClient?) {
		self.client = client
		clientId = client?.uniqueIdentifier

		if let client {
			client.updateStoredConfiguration()
			config = client.config.mutableCopy() as? MutableClientConfig ?? MutableClientConfig()
		} else {
			config = MutableClientConfig()
		}

		super.init(window: nil)
		prepareInitialState()
		loadConfig()
	}

	private var addressBookList: [AddressBookEntry] {
		addressBookArrayController.arrangedObjects as? [AddressBookEntry] ?? []
	}

	private var channelList: [ChannelConfig] {
		channelListArrayController.arrangedObjects as? [ChannelConfig] ?? []
	}

	private var highlightList: [HighlightMatchCondition] {
		highlightListArrayController.arrangedObjects as? [HighlightMatchCondition] ?? []
	}

	private var serverList: [Server] {
		serverListArrayController.arrangedObjects as? [Server] ?? []
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

	private func configureValidatedFields() {
		configure(alternateNicknamesTextField, invalidOnEmpty: false, firstTokenOnly: false) { value in
			for nickname in value.components(separatedBy: .whitespaces)
				where !ServerPropertiesValidation.isNickname(nickname)
			{
				return LocalizedKey("TDCServerPropertiesSheet[wlz-tb]", nickname)
			}
			return nil
		}

		configure(awayNicknameTextField, invalidOnEmpty: false, firstTokenOnly: true) { value in
			ServerPropertiesValidation.isNickname(value) ? nil : LocalizedKey("CommonErrors[och-j5]")
		}
		configure(nicknameTextField, invalidOnEmpty: true, firstTokenOnly: true) { value in
			ServerPropertiesValidation.isNickname(value) ? nil : LocalizedKey("CommonErrors[och-j5]")
		}
		configure(usernameTextField, invalidOnEmpty: true, firstTokenOnly: true) { value in
			ServerPropertiesValidation.isUsername(value) ? nil : LocalizedKey("TDCServerPropertiesSheet[8iw-q8]")
		}
		configure(ctcpVersionReplyTextField, invalidOnEmpty: false, firstTokenOnly: false)
		configure(realNameTextField, invalidOnEmpty: true, firstTokenOnly: false) { value in
			ServerPropertiesValidation.isSingleLine(value) ? nil : LocalizedKey("TDCServerPropertiesSheet[agy-bp]")
		}

		let leavingCommentValidation: (String) -> String? = { value in
			if !ServerPropertiesValidation.isSingleLine(value) {
				return LocalizedKey("CommonErrors[gas-v8]")
			}
			return value.count > 390 ? LocalizedKey("CommonErrors[2cb-af]", 390) : nil
		}
		configure(
			normalLeavingCommentTextField,
			invalidOnEmpty: false,
			firstTokenOnly: false,
			validation: leavingCommentValidation
		)
		configure(
			sleepModeQuitMessageTextField,
			invalidOnEmpty: false,
			firstTokenOnly: false,
			validation: leavingCommentValidation
		)
		configure(connectionNameTextField, invalidOnEmpty: true, firstTokenOnly: false) { value in
			ServerPropertiesValidation.isSingleLine(value) ? nil : LocalizedKey("CommonErrors[gas-v8]")
		}
		configure(serverPortTextField, invalidOnEmpty: true, firstTokenOnly: false) { value in
			ServerPropertiesValidation.isInternetPort(value) ? nil : LocalizedKey("CommonErrors[l0c-nb]")
		}

		serverAddressComboBox.textDidChangeCallback = self
		serverAddressComboBox.stringValueIsInvalidOnEmpty = true
		serverAddressComboBox.stringValueIsTrimmed = true
		serverAddressComboBox.stringValueUsesOnlyFirstToken = true
		serverAddressComboBox.validationBlock = { value in
			ServerPropertiesValidation.isInternetAddress(value) ? nil : LocalizedKey("CommonErrors[yyx-l3]")
		}

		configure(proxyAddressTextField, invalidOnEmpty: false, firstTokenOnly: true) { [weak self] value in
			guard let self else { return nil }
			guard [5, 6].contains(proxyTypeButton.selectedTag()) else { return nil }
			return ServerPropertiesValidation
				.isInternetAddress(value) ? nil : LocalizedKey("TDCServerPropertiesSheet[tlo-b6]")
		}
		proxyAddressTextField.performValidationWhenEmpty = true

		configure(proxyPortTextField, invalidOnEmpty: false, firstTokenOnly: false) { [weak self] value in
			guard let self else { return nil }
			guard [5, 6].contains(proxyTypeButton.selectedTag()) else { return nil }
			return ServerPropertiesValidation.isInternetPort(value) ? nil : LocalizedKey("CommonErrors[l0c-nb]")
		}
		proxyPortTextField.performValidationWhenEmpty = true
		proxyPortTextField.defaultValue = String(IRCConnectionDefaultProxyPort)
	}

	private func configure(
		_ textField: ValidatedTextField,
		invalidOnEmpty: Bool,
		firstTokenOnly: Bool,
		validation: ((String) -> String?)? = nil
	) {
		textField.textDidChangeCallback = self
		textField.stringValueIsInvalidOnEmpty = invalidOnEmpty
		textField.stringValueIsTrimmed = true
		textField.stringValueUsesOnlyFirstToken = firstTokenOnly
		textField.validationBlock = validation
	}

	private func configureTables() {
		for table in [addressBookTable, channelListTable, highlightsTable] {
			table?.target = self
			table?.doubleAction = #selector(tableViewDoubleClicked(_:))
			table?.registerForDraggedTypes([serverPropertiesTableDragToken])
			table?.draggingDestinationFeedbackStyle = .gap
		}
	}

	private func populateTabViewList() {
		func child(_ key: String, _ selection: ServerPropertiesSelection,
		           _ view: NSView) -> ContentNavigationOutlineViewItem
		{
			ContentNavigationOutlineViewItem(
				label: LocalizedKey(key),
				identifier: selection.rawValue,
				view: view,
				firstResponder: nil
			)
		}
		func group(_ key: String, _ children: [ContentNavigationOutlineViewItem]) -> ContentNavigationOutlineViewItem {
			ContentNavigationOutlineViewItem(
				label: LocalizedKey(key),
				identifier: 0,
				view: nil,
				firstResponder: nil,
				children: children
			)
		}

		let general = [
			child("TDCServerPropertiesSheet[8zc-6y]", .addressBook, contentViewAddressBook),
			child("TDCServerPropertiesSheet[5oz-07]", .autojoin, contentViewAutojoin),
			child("TDCServerPropertiesSheet[hip-13]", .connectCommands, contentViewConnectCommands),
			child("TDCServerPropertiesSheet[8ug-ka]", .encoding, contentViewEncoding),
			child("TDCServerPropertiesSheet[ehx-4d]", .general, contentViewGeneral),
			child("TDCServerPropertiesSheet[8ik-qo]", .identity, contentViewIdentity),
			child("TDCServerPropertiesSheet[jtx-hn]", .highlights, contentViewHighlights),
			child("TDCServerPropertiesSheet[j34-yr]", .disconnectMessages, contentViewDisconnectMessages),
		]
		let vendor = [child("TDCServerPropertiesSheet[fsj-7f]", .zncBouncer, contentViewZncBouncer)]
		let advanced = [
			child("TDCServerPropertiesSheet[ce7-kc]", .clientCertificate, contentViewClientCertificate),
			child("TDCServerPropertiesSheet[fcr-w8]", .floodControl, contentViewFloodControl),
			child("TDCServerPropertiesSheet[ffy-xt]", .networkSocket, contentViewNetworkSocket),
			child("TDCServerPropertiesSheet[t52-7a]", .proxyServer, contentViewProxyServer),
			child("TDCServerPropertiesSheet[36n-u9]", .redundancy, contentViewRedundancy),
		]

		let tree = [
			group("TDCServerPropertiesSheet[lww-pc]", general),
			group("TDCServerPropertiesSheet[v27-8w]", vendor),
			group("TDCServerPropertiesSheet[8uw-tz]", advanced),
		]
		navigationOutlineView.navigationTreeMatrix = tree
		navigationOutlineView.contentViewPreferredWidth = 100
		navigationOutlineView.contentViewPreferredHeight = 100
		navigationOutlineView.expandParentOnDoubleClick = true
		navigationOutlineView.expandItem(tree[0])
	}

	private func populateEncodings() {
		primaryEncodingButton.removeAllItems()
		fallbackEncodingButton.removeAllItems()
		encodingList = NSString.supportedStringEncodings(withTitle: false)
		var names = (encodingList as NSDictionary).sortedDictionaryKeys as? [String] ?? []
		let utf8Title = String.localizedName(of: .utf8)
		names.removeAll { $0 == utf8Title }
		primaryEncodingButton.addItem(withTitle: utf8Title)
		fallbackEncodingButton.addItem(withTitle: utf8Title)
		let favored = ["Unicode", "Western", "Central European"]
		populateEncodingPopup(names, preferredEncodings: favored, ignoreFavored: false)
		if UserDefaults.standard.bool(forKey: "Server Properties Window Sheet -> Include Advanced Encodings") {
			populateEncodingPopup(names, preferredEncodings: favored, ignoreFavored: true)
		}
	}

	private func populateEncodingPopup(_ encodings: [String], preferredEncodings: [String], ignoreFavored: Bool) {
		var previousPrefix: String?
		for encoding in encodings {
			guard let range = encoding.range(of: " (", range: encoding.startIndex ..< encoding.endIndex)
			else { continue }
			let prefix = String(encoding[..<range.lowerBound])
			let favored = preferredEncodings.contains(prefix)
			guard ignoreFavored ? !favored : favored else { continue }
			if prefix != previousPrefix {
				previousPrefix = prefix
				primaryEncodingButton.menu?.addItem(.separator())
				fallbackEncodingButton.menu?.addItem(.separator())
			}
			primaryEncodingButton.addItem(withTitle: encoding)
			fallbackEncodingButton.addItem(withTitle: encoding)
		}
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

	private func navigate(to requestedSelection: ServerPropertiesSelection) {
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
		clearChannelListPredicate()
		saveConfig()
		let selector = NSSelectorFromString("serverPropertiesSheet:onOk:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self, with: config.copy() as AnyObject)
		}
		super.ok(sender)
	}

	private func okOrError() -> Bool {
		let current = ServerPropertiesSelection(rawValue: navigationOutlineView.selectedItem?.identifier ?? 0) ??
			.default
		guard okOrError(for: current) else { return false }
		for selection in [ServerPropertiesSelection.general, .identity, .disconnectMessages, .proxyServer]
			where selection != current
		{
			guard okOrError(for: selection) else { return false }
		}
		return true
	}

	private func okOrError(for selection: ServerPropertiesSelection) -> Bool {
		let fields: [AnyObject]
		switch selection {
		case .general: fields = [connectionNameTextField, serverAddressComboBox, serverPortTextField]
		case .identity: fields = [
				nicknameTextField,
				awayNicknameTextField,
				alternateNicknamesTextField,
				usernameTextField,
				realNameTextField,
			]
		case .disconnectMessages: fields = [normalLeavingCommentTextField, sleepModeQuitMessageTextField]
		case .proxyServer: fields = [proxyAddressTextField, proxyPortTextField]
		default: return true
		}
		for field in fields {
			let isValid = (field as? ValidatedTextField)?.valueIsValid ?? (field as? ValidatedComboBox)?
				.valueIsValid ?? true
			if !isValid {
				navigate(to: selection)
				DispatchQueue.main.async {
					(field as? ValidatedTextField)?.showValidationErrorPopover()
					(field as? ValidatedComboBox)?.showValidationErrorPopover()
				}
				return false
			}
		}
		return true
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
			with: sheet.deepest,
			body: LocalizedKey("TDCServerPropertiesSheet[oz4-kb]"),
			title: LocalizedKey("TDCServerPropertiesSheet[bzh-il]"),
			defaultButton: LocalizedKey("Prompts[mvh-ms]"),
			alternateButton: LocalizedKey("Prompts[99q-gg]"),
			otherButton: nil
		) { [weak self] response, _, _ in
			guard response == .default, let self else { return }
			close()
			client.updateStoredConfiguration()
			config = client.config.mutableCopy() as? MutableClientConfig ?? MutableClientConfig()
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

		nicknameTextField.stringValue = config.nickname.isEmpty ? TPCPreferences.defaultNickname() : config.nickname
		awayNicknameTextField.stringValue = config.awayNickname ?? ""
		alternateNicknamesTextField.stringValue = config.alternateNicknames.joined(separator: " ")
		usernameTextField.stringValue = config.username.isEmpty ? TPCPreferences.defaultUsername() : config.username
		ctcpVersionReplyTextField.stringValue = config.ctcpVersionReply ?? ""
		realNameTextField.stringValue = config.realName.isEmpty ? TPCPreferences.defaultRealName() : config.realName
		nicknamePasswordTextField.stringValue = config.nicknamePassword ?? ""
		autojoinWaitsForNickServCheck.state = config.autojoinWaitsForNickServ ? .on : .off
		hideAutojoinDelayedWarningsCheck.state = config.hideAutojoinDelayedWarnings ? .off : .on

		normalLeavingCommentTextField.stringValue = config.normalLeavingComment
		sleepModeQuitMessageTextField.stringValue = config.sleepModeLeavingComment

		let encodings = encodingList as NSDictionary
		if let title = encodings.firstKey(for: NSNumber(value: config.primaryEncoding)) as? String {
			primaryEncodingButton.selectItem(withTitle: title)
		}
		if let title = encodings.firstKey(for: NSNumber(value: config.fallbackEncoding)) as? String {
			fallbackEncodingButton.selectItem(withTitle: title)
		}

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

		clearChannelListPredicate()
		addressBookArrayController.removeAllArrangedObjects()
		channelListArrayController.removeAllArrangedObjects()
		highlightListArrayController.removeAllArrangedObjects()
		serverListArrayController.removeAllArrangedObjects()
		addressBookArrayController.add(contentsOf: config.ignoreList)
		channelListArrayController.add(contentsOf: config.channelList)
		highlightListArrayController.add(contentsOf: config.highlightList)
		serverListArrayController.add(contentsOf: config.serverList)

		loadPrimaryServerEndpoint()
		setChannelListPredicate()
		updateAddressBookPage()
		updateChannelListPage()
		updateClientCertificatePage()
		updateHighlightsPage()
		updateIdentityPage()
		preferredCipherSuitesChanged(nil)
		proxyTypeChanged(nil)
	}

	private func loadPrimaryServerEndpoint() {
		guard let server = serverList.first else {
			serverAddressComboBox.stringValue = ""
			serverPortTextField.integerValue = Int(IRCConnectionDefaultServerPort)
			prefersSecuredConnectionCheck.state = .off
			serverPasswordTextField.stringValue = ""
			return
		}

		populatingPrimaryServer = true
		if let network = networkList.network(withServerAddress: server.serverAddress) {
			serverAddressComboBox.stringValue = network.networkName
		} else {
			serverAddressComboBox.stringValue = server.serverAddress
		}
		serverPortTextField.integerValue = Int(server.serverPort)
		prefersSecuredConnectionCheck.state = server.prefersSecuredConnection ? .on : .off
		serverPasswordTextField.stringValue = server.serverPassword ?? ""
		populatingPrimaryServer = false
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
			.cipherSuites = RCMCipherSuiteCollection(rawValue: UInt(preferredCipherSuitesButton.selectedTag())) ??
			.default

		config.nickname = nicknameTextField.value
		config.username = usernameTextField.value
		config.realName = realNameTextField.value
		let versionReply = ctcpVersionReplyTextField.value
		config.ctcpVersionReply = versionReply.isEmpty ? nil : versionReply
		config.awayNickname = awayNicknameTextField.value
		config.nicknamePassword = (nicknamePasswordTextField.stringValue as NSString).trim
		config.autojoinWaitsForNickServ = autojoinWaitsForNickServCheck.state == .on
		config.hideAutojoinDelayedWarnings = hideAutojoinDelayedWarningsCheck.state != .on
		config.alternateNicknames = uniqueNonempty(
			alternateNicknamesTextField.value.components(separatedBy: .whitespaces)
		)

		config.sleepModeLeavingComment = sleepModeQuitMessageTextField.value
		config.normalLeavingComment = normalLeavingCommentTextField.value
		config.primaryEncoding = encodingList[primaryEncodingButton.title]?.uintValue ?? String.Encoding.utf8.rawValue
		config.fallbackEncoding = encodingList[fallbackEncodingButton.title]?.uintValue ?? String.Encoding.isoLatin1
			.rawValue

		config.proxyType = IRCConnectionProxyType(rawValue: UInt(proxyTypeButton.selectedTag())) ?? .automatic
		config.proxyAddress = proxyAddressTextField.lowercaseValue
		config.proxyPort = UInt16(clamping: proxyPortTextField.integerValue)
		config.proxyUsername = (proxyUsernameTextField.stringValue as NSString).trimAndGetFirstToken
		config.proxyPassword = (proxyPasswordTextField.stringValue as NSString).trim
		config.loginCommands = connectCommandsField.string
			.components(separatedBy: .newlines)
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
		config.setInvisibleModeOnConnect = setInvisibleModeOnConnectCheck.state == .on
		config.runConnectCommandsSilently = runConnectCommandsSilentlyCheck.state == .on
		config.floodControlMaximumMessages = UInt(floodControlMessageCountSlider.integerValue)
		config.floodControlDelayTimerInterval = UInt(floodControlDelayTimerSlider.integerValue)
		config.channelList = channelList
		config.highlightList = highlightList
		config.ignoreList = addressBookList
		config.serverList = serverList
	}

	private func uniqueNonempty(_ values: [String]) -> [String] {
		var seen = Set<String>()
		return values.filter { !$0.isEmpty && seen.insert($0).inserted }
	}

	private func restorePreviousValuesForPrimaryServer() {
		guard let previousPrimaryServer else { return }
		populatingPrimaryServer = true
		serverPortTextField.integerValue = Int(previousPrimaryServer.serverPort)
		prefersSecuredConnectionCheck.state = previousPrimaryServer.prefersSecuredConnection ? .on : .off
		self.previousPrimaryServer = nil
		populatingPrimaryServer = false
	}

	private func saveCurrentValuesForPrimaryServer() {
		guard previousPrimaryServer == nil else { return }
		if let server = serverList.first {
			previousPrimaryServer = server
			return
		}
		let server = MutableServer()
		server.serverPort = UInt16(clamping: serverPortTextField.integerValue)
		server.prefersSecuredConnection = prefersSecuredConnectionCheck.state == .on
		previousPrimaryServer = server
	}

	private func populateDefaultsForPreconfiguredNetwork() {
		guard !populatingPrimaryServer else { return }
		let address = serverAddressComboBox.value
		guard address != lastServerAddressValue else { return }
		lastServerAddressValue = address
		guard let network = networkList.network(named: address) ?? networkList.network(withServerAddress: address)
		else {
			restorePreviousValuesForPrimaryServer()
			return
		}

		populatingPrimaryServer = true
		if !serverAddressComboBox.valueIsPredefined {
			serverAddressComboBox.stringValue = network.networkName
			lastServerAddressValue = network.networkName
		}
		saveCurrentValuesForPrimaryServer()
		serverPortTextField.integerValue = Int(network.serverPort)
		prefersSecuredConnectionCheck.state = network.prefersSecuredConnection ? .on : .off
		populatingPrimaryServer = false
	}

	private func updateChannelListPage() {
		let enabled = channelListTable.selectedRow >= 0
		deleteChannelButton.isEnabled = enabled
		editChannelButton.isEnabled = enabled
	}

	private func clearChannelListPredicate() {
		channelListArrayController.filterPredicate = nil
	}

	private func setChannelListPredicate() {
		channelListArrayController.filterPredicate = NSPredicate(format: "type == 0")
	}

	private func unfilteredChannelIndex(identifier: String) -> Int? {
		let all = channelListArrayController.arrangedObjects as? [ChannelConfig] ?? []
		return all.firstIndex { $0.uniqueIdentifier == identifier }
	}

	private func storeChannelConfig(_ config: ChannelConfig) {
		clearChannelListPredicate()
		if let index = unfilteredChannelIndex(identifier: config.uniqueIdentifier) {
			channelListArrayController.replaceObject(atArrangedObjectIndex: UInt(index), with: config)
		} else {
			channelListArrayController.addObject(config)
		}
		setChannelListPredicate()
	}

	private func removeChannelConfig(_ config: ChannelConfig) {
		clearChannelListPredicate()
		if let index = unfilteredChannelIndex(identifier: config.uniqueIdentifier) {
			channelListArrayController.removeObject(UInt(index))
		}
		setChannelListPredicate()
	}

	private func moveChannelConfig(_ config: ChannelConfig, above target: ChannelConfig?) {
		clearChannelListPredicate()
		guard let from = unfilteredChannelIndex(identifier: config.uniqueIdentifier) else {
			setChannelListPredicate()
			return
		}
		let count = (channelListArrayController.arrangedObjects as? [Any])?.count ?? 0
		let to = target.flatMap { unfilteredChannelIndex(identifier: $0.uniqueIdentifier) } ?? count
		if from != to {
			channelListArrayController.moveObject(atArrangedObjectIndex: UInt(from), to: UInt(to))
		}
		setChannelListPredicate()
	}

	private func updateAddressBookPage() {
		let enabled = addressBookTable.selectedRow >= 0
		deleteAddressBookEntryButton.isEnabled = enabled
		editAddressBookEntryButton.isEnabled = enabled
	}

	private func updateHighlightsPage() {
		let enabled = highlightsTable.selectedRow >= 0
		deleteHighlightButton.isEnabled = enabled
		editHighlightButton.isEnabled = enabled
	}

	@IBAction private func useSSLCheckChanged(_: Any?) {
		let secured = prefersSecuredConnectionCheck.state == .on
		if secured, serverPortTextField.integerValue == 6667 {
			serverPortTextField.stringValue = "6697"
		} else if !secured, serverPortTextField.integerValue == 6697 {
			serverPortTextField.stringValue = "6667"
		}
		rebuildMutableServerEndpointListIfNeeded()
	}

	private func updateIdentityPage() {
		hideAutojoinDelayedWarningsCheck.isHidden = autojoinWaitsForNickServCheck.state == .off
	}

	public func controlTextDidChange(_ notification: Notification) {
		if notification.object as AnyObject? === serverPasswordTextField {
			rebuildMutableServerEndpointListIfNeeded()
		}
	}

	@objc public func validatedTextFieldTextDidChange(_ sender: Any) {
		if sender as AnyObject === serverAddressComboBox {
			populateDefaultsForPreconfiguredNetwork()
			rebuildMutableServerEndpointListIfNeeded()
		} else if sender as AnyObject === serverPortTextField {
			rebuildMutableServerEndpointListIfNeeded()
		}
	}

	@IBAction private func autojoinWaitsForNickServChanged(_: Any?) {
		updateIdentityPage()
		guard autojoinWaitsForNickServCheck.state == .on else { return }
		guard nicknamePasswordTextField.stringValue.isEmpty,
		      !clientCertificateResetCertificateButton.isEnabled else { return }
		_ = TDCAlert.modalAlert(
			withMessage: LocalizedKey("TDCServerPropertiesSheet[26u-j8]"),
			title: LocalizedKey("TDCServerPropertiesSheet[94r-eq]"),
			defaultButton: LocalizedKey("Prompts[c7s-dq]"),
			alternateButton: nil
		)
	}

	@IBAction private func preferredCipherSuitesChanged(_: Any?) {
		viewListOfPreferredCipherSuitesButton.isEnabled = preferredCipherSuitesButton
			.selectedTag() != Int(RCMCipherSuiteCollection.none.rawValue)
	}

	@IBAction private func preferredCipherSuitesViewList(_: Any?) {
		let collection = RCMCipherSuiteCollection(rawValue: UInt(preferredCipherSuitesButton.selectedTag())) ?? .default
		let descriptions = RCMSecureTransport
			.descriptions(forCipherListCollection: collection, withProtocol: true)
		TDCAlert.alertSheet(
			with: sheet,
			body: LocalizedKey("TDCServerPropertiesSheet[k50-8n]", descriptions.joined(separator: "\n")),
			title: LocalizedKey(
				"TDCServerPropertiesSheet[yko-5g]",
				preferredCipherSuitesButton.titleOfSelectedItem ?? ""
			),
			defaultButton: LocalizedKey("Prompts[c7s-dq]"),
			alternateButton: nil,
			otherButton: nil
		)
	}

	@IBAction private func proxyTypeChanged(_: Any?) {
		let proxyType = IRCConnectionProxyType(rawValue: UInt(proxyTypeButton.selectedTag())) ?? .none
		let isAutomatic = proxyType == .automatic
		let isTor = proxyType == .tor
		let socks = proxyType == .socks5
		let http = proxyType.rawValue == 6
		let enabled = socks || http
		contentViewProxyServerInputView.isHidden = !enabled
		contentViewProxyServerTorBrowserView.isHidden = !isTor
		contentViewProxyServerSystemSocksView.isHidden = !isAutomatic
		proxyAddressTextField.isEnabled = enabled
		proxyPortTextField.isEnabled = enabled
		proxyUsernameTextField.isEnabled = socks
		proxyPasswordTextField.isEnabled = socks
		proxyAddressTextField.performValidation()
		proxyPortTextField.performValidation()
	}

	@IBAction private func openProxySettingsInSystemPreferences(_: Any?) {
		PreferencesController.openProxySettingsInSystemPreferences()
	}

	@IBAction private func toggleAdvancedEncodings(_: Any?) {
		var primary = primaryEncodingButton.titleOfSelectedItem
		var fallback = fallbackEncodingButton.titleOfSelectedItem
		populateEncodings()
		if primary.flatMap({ primaryEncodingButton.item(withTitle: $0) }) == nil {
			primary = String.localizedName(of: .utf8)
		}
		if fallback.flatMap({ fallbackEncodingButton.item(withTitle: $0) }) == nil {
			fallback = String.localizedName(of: .isoLatin1)
		}
		if let primary {
			primaryEncodingButton.selectItem(withTitle: primary)
		}
		if let fallback {
			fallbackEncodingButton.selectItem(withTitle: fallback)
		}
	}

	@IBAction private func preferredInternetProtocolChanged(_ sender: Any?) {
		config.connectionPrefersIPv4 = false
		let tag = (sender as? NSControl)?.tag ?? 0
		config.addressType = IRCConnectionAddressType(rawValue: UInt(tag)) ?? .default
	}

	private func copyCertificateCommand(from field: NSTextField) {
		NSPasteboard.general.stringContent = "/msg NickServ cert add \(field.stringValue)"
	}

	@IBAction private func onClientCertificateFingerprintSHA512CopyRequested(_: Any?) {
		copyCertificateCommand(from: clientCertificateSHA512FingerprintField)
	}

	@IBAction private func onClientCertificateFingerprintSHA2CopyRequested(_: Any?) {
		copyCertificateCommand(from: clientCertificateSHA2FingerprintField)
	}

	@IBAction private func onClientCertificateFingerprintSHA1CopyRequested(_: Any?) {
		copyCertificateCommand(from: clientCertificateSHA1FingerprintField)
	}

	private struct CertificateDetails {
		let commonName: String
		let sha512: String
		let sha256: String
		let sha1: String
	}

	private func clientCertificateDetails() -> CertificateDetails? {
		guard let persistentReference = config.identityClientSideCertificate else { return nil }
		let query: [CFString: Any] = [
			kSecClass: kSecClassCertificate,
			kSecValuePersistentRef: persistentReference,
			kSecReturnRef: true,
		]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      let certificate = result as! SecCertificate?
		else { return nil }

		var commonNameReference: CFString?
		guard SecCertificateCopyCommonName(certificate, &commonNameReference) == errSecSuccess,
		      let commonName = commonNameReference as String?
		else { return nil }

		let data = SecCertificateCopyData(certificate) as Data
		return CertificateDetails(
			commonName: commonName,
			sha512: (data as NSData).sha512,
			sha256: (data as NSData).sha256,
			sha1: (data as NSData).sha1
		)
	}

	private func saveClientCertificate(identity: SecIdentity) {
		var certificate: SecCertificate?
		guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { return }
		let query: [CFString: Any] = [
			kSecClass: kSecClassCertificate,
			kSecValueRef: certificate,
			kSecReturnPersistentRef: true,
		]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      let persistentReference = result as? Data
		else { return }
		config.identityClientSideCertificate = persistentReference
		if prefersSecuredConnectionCheck.state == .off {
			prefersSecuredConnectionCheck.state = .on
			useSSLCheckChanged(nil)
		}
	}

	private func updateClientCertificatePage() {
		let details = clientCertificateDetails()
		let emptyValue = LocalizedKey("TDCServerPropertiesSheet[6xz-ec]")
		clientCertificateCommonNameField.stringValue = details?.commonName ?? emptyValue
		clientCertificateSHA512FingerprintField.stringValue = details?.sha512.uppercased() ?? emptyValue
		clientCertificateSHA2FingerprintField.stringValue = details?.sha256.uppercased() ?? emptyValue
		clientCertificateSHA1FingerprintField.stringValue = details?.sha1.uppercased() ?? emptyValue
		let hasCertificate = details != nil
		clientCertificateResetCertificateButton.isEnabled = hasCertificate
		clientCertificateSHA512FingerprintCopyButton.isEnabled = hasCertificate
		clientCertificateSHA2FingerprintCopyButton.isEnabled = hasCertificate
		clientCertificateSHA1FingerprintCopyButton.isEnabled = hasCertificate
	}

	@IBAction private func onClientCertificateResetRequested(_: Any?) {
		config.identityClientSideCertificate = nil
		updateClientCertificatePage()
	}

	@IBAction private func onClientCertificateChangeRequested(_: Any?) {
		let query: [CFString: Any] = [
			kSecClass: kSecClassIdentity,
			kSecMatchLimit: kSecMatchLimitAll,
			kSecReturnRef: true,
		]
		var result: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		guard status == errSecSuccess, let identities = result as? [SecIdentity], !identities.isEmpty else {
			_ = TDCAlert.alert(
				withMessage: LocalizedKey("TDCServerPropertiesSheet[489-hG]"),
				title: LocalizedKey("TDCServerPropertiesSheet[pmk-os]"),
				defaultButton: LocalizedKey("Prompts[c7s-dq]"),
				alternateButton: nil
			)
			return
		}

		guard let panel = SFChooseIdentityPanel.shared() else { return }
		clientCertificateSelectCertificatePanel = panel
		panel.setInformativeText(LocalizedKey("TDCServerPropertiesSheet[mi4-fd]"))
		panel.setAlternateButtonTitle(LocalizedKey("Prompts[qso-2g]"))
		panel.beginSheet(
			for: sheet,
			modalDelegate: self,
			didEnd: #selector(chooseIdentityPanelDidEnd(_:returnCode:contextInfo:)),
			contextInfo: nil,
			identities: identities,
			message: LocalizedKey("TDCServerPropertiesSheet[6wq-i4]")
		)
	}

	@objc private func chooseIdentityPanelDidEnd(
		_ panel: SFChooseIdentityPanel,
		returnCode: Int,
		contextInfo _: UnsafeMutableRawPointer?
	) {
		if returnCode == NSApplication.ModalResponse.OK.rawValue,
		   let identity = panel.identity()?.takeUnretainedValue()
		{
			saveClientCertificate(identity: identity)
			updateClientCertificatePage()
		}
		clientCertificateSelectCertificatePanel = nil
	}

	@IBAction private func editSeverEndpoints(_: Any?) {
		let controller = ServerEndpointListSheet(window: sheet)
		controller.delegate = self
		controller.start(with: serverList)
		serverEndpointSheet = controller
	}

	@objc(serverEndpointListSheet:onOk:)
	public func serverEndpointListSheet(_: ServerEndpointListSheet, onOk serverList: [Server]) {
		serverListArrayController.removeAllArrangedObjects()
		serverListArrayController.add(contentsOf: serverList)
		loadPrimaryServerEndpoint()
	}

	@objc(serverEndpointListSheetWillClose:)
	public func serverEndpointListSheetWillClose(_: ServerEndpointListSheet) {
		serverEndpointSheet = nil
	}

	private func rebuildMutableServerEndpointList() {
		guard !populatingPrimaryServer else { return }
		let server = serverList.first?.mutableCopy() as? MutableServer ?? MutableServer()
		let address = serverAddressComboBox.value
		server.serverAddress = networkList.network(named: address)?.serverAddress ?? address.lowercased()
		server.serverPort = UInt16(clamping: serverPortTextField.integerValue)
		server.prefersSecuredConnection = prefersSecuredConnectionCheck.state == .on
		server.serverPassword = (serverPasswordTextField.stringValue as NSString).trim
		let immutable = server.copy() as! Server
		if serverList.isEmpty {
			serverListArrayController.addObject(immutable)
		} else {
			serverListArrayController.replaceObject(atArrangedObjectIndex: 0, with: immutable)
		}
	}

	private func rebuildMutableServerEndpointListIfNeeded() {
		guard serverEndpointSheet == nil else { return }
		rebuildMutableServerEndpointList()
	}

	@IBAction private func addHighlight(_: Any?) {
		let controller = HighlightEntrySheet(config: nil)
		controller.delegate = self
		controller.window = sheet
		controller.start(with: channelList)
		highlightSheet = controller
	}

	@IBAction private func editHighlight(_: Any?) {
		let row = highlightsTable.selectedRow
		guard highlightList.indices.contains(row) else { return }
		let controller = HighlightEntrySheet(config: highlightList[row])
		controller.delegate = self
		controller.window = sheet
		controller.start(with: channelList)
		highlightSheet = controller
	}

	@objc(highlightEntrySheet:onOk:)
	public func highlightEntrySheet(_: HighlightEntrySheet, onOk config: HighlightMatchCondition) {
		if let index = highlightList.firstIndex(where: { $0.uniqueIdentifier == config.uniqueIdentifier }) {
			highlightListArrayController.replaceObject(atArrangedObjectIndex: UInt(index), with: config)
		} else {
			highlightListArrayController.addObject(config)
		}
	}

	@objc(highlightEntrySheetWillClose:)
	public func highlightEntrySheetWillClose(_: HighlightEntrySheet) {
		highlightSheet = nil
	}

	@IBAction private func deleteHighlight(_: Any?) {
		removeSelectedRow(
			from: highlightsTable,
			controller: highlightListArrayController,
			remainingCount: { self.highlightList.count }
		)
	}

	@IBAction private func addChannel(_: Any?) {
		let controller = ChannelPropertiesSheet(config: nil)
		controller.delegate = self
		controller.window = sheet
		controller.start()
		channelSheet = controller
	}

	@IBAction private func editChannel(_: Any?) {
		let row = channelListTable.selectedRow
		guard channelList.indices.contains(row) else { return }
		let controller = ChannelPropertiesSheet(config: channelList[row])
		controller.delegate = self
		controller.window = sheet
		controller.start()
		channelSheet = controller
	}

	@objc(channelPropertiesSheet:onOk:)
	public func channelPropertiesSheet(_: ChannelPropertiesSheet, onOk config: ChannelConfig) {
		storeChannelConfig(config)
	}

	@objc(channelPropertiesSheetWillClose:)
	public func channelPropertiesSheetWillClose(_: ChannelPropertiesSheet) {
		channelSheet = nil
	}

	@IBAction private func deleteChannel(_: Any?) {
		let row = channelListTable.selectedRow
		guard channelList.indices.contains(row) else { return }
		removeChannelConfig(channelList[row])
		selectNearestRow(in: channelListTable, previousRow: row, remainingCount: channelList.count)
	}

	@IBAction private func showAddAddressBookEntryMenu(_ sender: Any?) {
		guard let view = sender as? NSView else { return }
		addAddressBookEntryMenu.popUp(positioning: nil, at: .zero, in: view)
	}

	private func addIgnoreAddressBookEntry(withHostmask hostmask: String? = nil) {
		let controller = if let hostmask {
			AddressBookSheet(config: AddressBookEntry.newIgnoreEntry(forHostmask: hostmask))
		} else {
			AddressBookSheet(entryType: .ignore)
		}
		controller.delegate = self
		controller.window = sheet
		controller.start()
		addressBookSheet = controller
	}

	private func addUserTrackingAddressBookEntry() {
		let controller = AddressBookSheet(entryType: .userTracking)
		controller.delegate = self
		controller.window = sheet
		controller.start()
		addressBookSheet = controller
	}

	@IBAction private func addAddressBookEntry(_ sender: Any?) {
		switch (sender as? NSControl)?.tag {
		case 3: addIgnoreAddressBookEntry()
		case 4: addUserTrackingAddressBookEntry()
		default: break
		}
	}

	private func editAddressBookEntry(with entry: AddressBookEntry) {
		guard let index = addressBookList.firstIndex(where: { $0 === entry }) else { return }
		addressBookTable.selectItem(at: UInt(index))
		editAddressBookEntry(nil)
	}

	@IBAction private func editAddressBookEntry(_: Any?) {
		let row = addressBookTable.selectedRow
		guard addressBookList.indices.contains(row) else { return }
		let controller = AddressBookSheet(config: addressBookList[row])
		controller.delegate = self
		controller.window = sheet
		controller.start()
		addressBookSheet = controller
	}

	@objc(addressBookSheet:onOk:)
	public func addressBookSheet(_: AddressBookSheet, onOk config: AddressBookEntry) {
		if let index = addressBookList.firstIndex(where: { $0.uniqueIdentifier == config.uniqueIdentifier }) {
			addressBookArrayController.replaceObject(atArrangedObjectIndex: UInt(index), with: config)
		} else {
			addressBookArrayController.addObject(config)
		}
	}

	@objc(addressBookSheetWillClose:)
	public func addressBookSheetWillClose(_: AddressBookSheet) {
		addressBookSheet = nil
	}

	@IBAction private func deleteAddressBookEntry(_: Any?) {
		removeSelectedRow(
			from: addressBookTable,
			controller: addressBookArrayController,
			remainingCount: { self.addressBookList.count }
		)
	}

	private func removeSelectedRow(
		from table: BasicTableView,
		controller: NSArrayController,
		remainingCount: () -> Int
	) {
		let row = table.selectedRow
		guard row >= 0 else { return }
		controller.removeObject(UInt(row))
		selectNearestRow(in: table, previousRow: row, remainingCount: remainingCount())
	}

	private func selectNearestRow(in table: BasicTableView, previousRow: Int, remainingCount: Int) {
		guard remainingCount > 0 else { return }
		table.selectItem(at: UInt(min(previousRow, remainingCount - 1)))
	}

	@objc private func channelAutoJoinToggled(_ sender: NSButton) {
		let row = channelListTable.row(for: sender)
		guard channelList.indices.contains(row),
		      let config = channelList[row].mutableCopy() as? MutableChannelConfig else { return }
		config.autoJoin = sender.state == .on
		storeChannelConfig(config.copy() as! ChannelConfig)
	}

	@objc private func tableViewDoubleClicked(_ sender: Any?) {
		if sender as AnyObject === channelListTable {
			editChannel(sender)
		} else if sender as AnyObject === highlightsTable {
			editHighlight(sender)
		} else if sender as AnyObject === addressBookTable {
			editAddressBookEntry(sender)
		}
	}

	@objc public func windowWillClose(_: Notification) {
		removeConfigurationDidChangeObserver()
		for table in [addressBookTable, channelListTable, highlightsTable] {
			table?.delegate = nil
			table?.dataSource = nil
			table?.unregisterDraggedTypes()
		}
		sheet.makeFirstResponder(nil)
		let selector = NSSelectorFromString("serverPropertiesSheetWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}

extension ServerPropertiesSheet: NSTableViewDataSource, NSTableViewDelegate {
	public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let column = tableColumn else { return nil }
		let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView
		if tableView === channelListTable, column.identifier.rawValue == "join", channelList.indices.contains(row) {
			let checkbox = cell?.subviews.first as? NSButton
			checkbox?.state = channelList[row].autoJoin ? .on : .off
			checkbox?.target = self
			checkbox?.action = #selector(channelAutoJoinToggled(_:))
			return cell
		}
		cell?.textField?.stringValue = stringValue(for: tableView, column: column.identifier.rawValue, row: row) ?? ""
		return cell
	}

	private func stringValue(for tableView: NSTableView, column: String, row: Int) -> String? {
		if tableView === channelListTable, channelList.indices.contains(row) {
			let config = channelList[row]
			if column == "name" {
				return config.channelName
			}
			if column == "pass" {
				return config.secretKey ?? ""
			}
		} else if tableView === highlightsTable, highlightList.indices.contains(row) {
			let config = highlightList[row]
			if column == "keyword" {
				return config.matchKeyword
			}
			if column == "channel" {
				if let identifier = config.matchChannelId,
				   let channel = channelList.first(where: { $0.uniqueIdentifier == identifier })
				{
					return channel.channelName
				}
				return LocalizedKey("TDCServerPropertiesSheet[61f-6b]")
			}
			if column == "type" {
				return LocalizedKey(config
					.matchIsExcluded ? "TDCServerPropertiesSheet[qcc-b4]" : "TDCServerPropertiesSheet[tet-dk]")
			}
		} else if tableView === addressBookTable, addressBookList.indices.contains(row) {
			let config = addressBookList[row]
			if column == "hostmask" {
				return config.hostmask
			}
			if column == "type" {
				return LocalizedKey(config
					.entryType == .ignore ? "TDCServerPropertiesSheet[f7o-x4]" : "TDCServerPropertiesSheet[b0g-0x]")
			}
		}
		return nil
	}

	public func tableViewSelectionDidChange(_ notification: Notification) {
		guard let table = notification.object as? NSTableView else { return }
		if table === channelListTable {
			updateChannelListPage()
		} else if table === highlightsTable {
			updateHighlightsPage()
		} else if table === addressBookTable {
			updateAddressBookPage()
		}
	}

	public func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
		let item = NSPasteboardItem()
		item.setString(String(row), forType: serverPropertiesTableDragToken)
		return item
	}

	public func tableView(
		_ tableView: NSTableView,
		validateDrop _: any NSDraggingInfo,
		proposedRow row: Int,
		proposedDropOperation _: NSTableView.DropOperation
	) -> NSDragOperation {
		tableView.setDropRow(row, dropOperation: .above)
		return .move
	}

	public func tableView(
		_ tableView: NSTableView,
		acceptDrop info: any NSDraggingInfo,
		row: Int,
		dropOperation _: NSTableView.DropOperation
	) -> Bool {
		guard let value = info.draggingPasteboard.string(forType: serverPropertiesTableDragToken),
		      let draggedRow = Int(value),
		      draggedRow >= 0, draggedRow < tableView.numberOfRows
		else { return false }

		if tableView === channelListTable, channelList.indices.contains(draggedRow) {
			let target = channelList.indices.contains(row) ? channelList[row] : nil
			moveChannelConfig(channelList[draggedRow], above: target)
		} else if tableView === highlightsTable {
			highlightListArrayController.moveObject(atArrangedObjectIndex: UInt(draggedRow), to: UInt(row))
		} else if tableView === addressBookTable {
			addressBookArrayController.moveObject(atArrangedObjectIndex: UInt(draggedRow), to: UInt(row))
		}
		return true
	}
}
