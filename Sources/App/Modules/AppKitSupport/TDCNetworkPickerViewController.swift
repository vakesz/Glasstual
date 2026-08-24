/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

private enum NetworkPickerRowKind: UInt {
	case group = 0
	case network
	case custom
}

private let networkCellIdentifier = NSUserInterfaceItemIdentifier("NetworkCell")
private let groupCellIdentifier = NSUserInterfaceItemIdentifier("GroupCell")

// MARK: - Row Model

private final class NetworkPickerRow: NSObject {
	var kind: NetworkPickerRowKind = .group
	var title: String?
	var network: Network?

	class func groupRow(title: String) -> NetworkPickerRow {
		let row = NetworkPickerRow()
		row.kind = .group
		row.title = title
		return row
	}

	class func networkRow(_ network: Network) -> NetworkPickerRow {
		let row = NetworkPickerRow()
		row.kind = .network
		row.network = network
		row.title = network.networkName
		return row
	}

	class func customRow() -> NetworkPickerRow {
		let row = NetworkPickerRow()
		row.kind = .custom
		row.title = LocalizedKey("TDCOnboardingWindow[np1-cs]")
		return row
	}
}

// MARK: - Cell View

/* Name on the first line, description on the second, and a lock on the
 trailing edge when the network prefers TLS. */
private final class NetworkPickerCellView: NSTableCellView {
	var descriptionField: NSTextField!
	var lockImageView: NSImageView!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		prepareInitialState()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func prepareInitialState() {
		let nameField = NSTextField(labelWithString: "")
		nameField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
		nameField.lineBreakMode = .byTruncatingTail
		nameField.translatesAutoresizingMaskIntoConstraints = false

		let descriptionField = NSTextField(labelWithString: "")
		descriptionField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		descriptionField.textColor = .secondaryLabelColor
		descriptionField.lineBreakMode = .byTruncatingTail
		descriptionField.translatesAutoresizingMaskIntoConstraints = false

		let lockImageView = NSImageView(
			image: NSImage(
				systemSymbolName: "lock.fill",
				accessibilityDescription: LocalizedKey("TDCOnboardingWindow[np1-lk]")
			)!
		)
		lockImageView.contentTintColor = .secondaryLabelColor
		lockImageView.symbolConfiguration = NSImage.SymbolConfiguration(scale: .small)
		lockImageView.translatesAutoresizingMaskIntoConstraints = false
		lockImageView.setContentHuggingPriority(.required, for: .horizontal)

		addSubview(nameField)
		addSubview(descriptionField)
		addSubview(lockImageView)

		NSLayoutConstraint.activate([
			nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
			nameField.topAnchor.constraint(equalTo: topAnchor, constant: 4),
			nameField.trailingAnchor.constraint(lessThanOrEqualTo: lockImageView.leadingAnchor, constant: -8),
			descriptionField.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
			descriptionField.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 1),
			descriptionField.trailingAnchor.constraint(lessThanOrEqualTo: lockImageView.leadingAnchor, constant: -8),
			descriptionField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
			lockImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
			lockImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
		])

		textField = nameField
		self.descriptionField = descriptionField
		self.lockImageView = lockImageView
	}
}

// MARK: - Picker

@objc(TDCNetworkPickerViewController)
@MainActor
public final class NetworkPickerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
	NSSearchFieldDelegate, NSTextFieldDelegate
{
	@objc public weak var delegate: AnyObject?

	@objc public private(set) var networkList: NetworkList
	@objc public private(set) var selectedNetwork: Network?
	@objc public private(set) var customServerSelected = false

	private var rows: [NetworkPickerRow] = []
	private var searchField: NSSearchField!
	private var scrollView: NSScrollView!
	private var tableView: NSTableView!
	private var detailView: NSView!
	private var detailTitleField: NSTextField!
	private var registrationBadge: NSTextField!
	private var serverAddressField: NSTextField!
	private var serverPortField: NSTextField!
	private var securedCheck: NSButton!
	private var accountBox: NSBox!
	private var accountNameField: NSTextField!
	private var accountPasswordField: NSSecureTextField!
	private var saslCheck: NSButton!
	private var registrationNoteField: NSTextField!
	private var websiteButton: NSButton!
	private var accountNameEdited = false
	private var defaultNicknameStorage: String?

	@objc public var defaultNickname: String? {
		get { defaultNicknameStorage }
		set {
			defaultNicknameStorage = newValue

			if accountNameEdited == false, accountNameField != nil {
				accountNameField.stringValue = newValue ?? ""
			}
		}
	}

	@objc public init() {
		networkList = NetworkList()
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	public required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// MARK: - View

	override public func loadView() {
		let view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 380))
		view.translatesAutoresizingMaskIntoConstraints = false
		self.view = view

		buildListViews()
		buildDetailViews()
		reloadRows()
		updateDetailView()
	}

	private func buildListViews() {
		let searchField = NSSearchField()
		searchField.placeholderString = LocalizedKey("TDCOnboardingWindow[np1-sp]")
		searchField.delegate = self
		searchField.sendsSearchStringImmediately = true
		searchField.translatesAutoresizingMaskIntoConstraints = false

		let tableView = NSTableView()
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Network"))
		column.resizingMask = .autoresizingMask
		tableView.addTableColumn(column)

		tableView.headerView = nil
		tableView.style = .sourceList
		tableView.selectionHighlightStyle = .regular
		tableView.rowSizeStyle = .custom
		tableView.rowHeight = 38
		tableView.floatsGroupRows = true
		tableView.allowsEmptySelection = true
		tableView.allowsMultipleSelection = false
		tableView.usesAlternatingRowBackgroundColors = false
		tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
		tableView.dataSource = self
		tableView.delegate = self
		tableView.target = self
		tableView.doubleAction = #selector(tableViewDoubleClicked(_:))
		tableView.setAccessibilityLabel(LocalizedKey("TDCOnboardingWindow[np1-ax]"))

		let scrollView = NSScrollView()
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.borderType = .bezelBorder
		scrollView.translatesAutoresizingMaskIntoConstraints = false

		view.addSubview(searchField)
		view.addSubview(scrollView)

		NSLayoutConstraint.activate([
			searchField.topAnchor.constraint(equalTo: view.topAnchor),
			searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
			scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
		])

		self.searchField = searchField
		self.scrollView = scrollView
		self.tableView = tableView
	}

	private func makeLabel(_ title: String) -> NSTextField {
		let label = NSTextField(labelWithString: title)
		label.alignment = .right
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}

	private func buildDetailViews() {
		let detailView = NSView()
		detailView.translatesAutoresizingMaskIntoConstraints = false

		let titleField = NSTextField(labelWithString: "")
		titleField.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
		titleField.lineBreakMode = .byTruncatingTail
		titleField.translatesAutoresizingMaskIntoConstraints = false

		let badge = NSTextField(labelWithString: LocalizedKey("TDCOnboardingWindow[np1-rq]"))
		badge.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
		badge.textColor = .systemOrange
		badge.wantsLayer = true
		badge.layer?.cornerRadius = 4
		badge.layer?.borderWidth = 1
		badge.layer?.borderColor = NSColor.systemOrange.cgColor
		badge.alignment = .center
		badge.translatesAutoresizingMaskIntoConstraints = false
		badge.isHidden = true

		let addressLabel = makeLabel(LocalizedKey("TDCOnboardingWindow[np1-sv]"))

		let addressField = NSTextField(string: "")
		addressField.placeholderString = LocalizedKey("TDCOnboardingWindow[np1-sh]")
		addressField.delegate = self
		addressField.translatesAutoresizingMaskIntoConstraints = false

		let portLabel = makeLabel(LocalizedKey("TDCOnboardingWindow[np1-pt]"))

		let portField = NSTextField(string: "")
		portField.placeholderString = LocalizedKey("TDCOnboardingWindow[np1-pp]")
		portField.delegate = self
		portField.alignment = .right
		portField.translatesAutoresizingMaskIntoConstraints = false

		let portFormatter = NumberFormatter()
		portFormatter.numberStyle = .none
		portFormatter.minimum = 1
		portFormatter.maximum = 65535
		portFormatter.allowsFloats = false
		portFormatter.usesGroupingSeparator = false
		portField.formatter = portFormatter

		let securedCheck = NSButton(
			checkboxWithTitle: LocalizedKey("TDCOnboardingWindow[np1-tl]"),
			target: self,
			action: #selector(fieldChanged(_:))
		)
		securedCheck.translatesAutoresizingMaskIntoConstraints = false

		let accountBox = NSBox()
		accountBox.title = LocalizedKey("TDCOnboardingWindow[np1-ac]")
		accountBox.titlePosition = .atTop
		accountBox.translatesAutoresizingMaskIntoConstraints = false

		let accountNameLabel = makeLabel(LocalizedKey("TDCOnboardingWindow[np1-an]"))

		let accountNameField = NSTextField(string: "")
		accountNameField.delegate = self
		accountNameField.translatesAutoresizingMaskIntoConstraints = false

		let passwordLabel = makeLabel(LocalizedKey("TDCOnboardingWindow[np1-pw]"))

		let passwordField = NSSecureTextField()
		passwordField.delegate = self
		passwordField.translatesAutoresizingMaskIntoConstraints = false

		let saslCheck = NSButton(
			checkboxWithTitle: LocalizedKey("TDCOnboardingWindow[np1-sa]"),
			target: self,
			action: #selector(fieldChanged(_:))
		)
		saslCheck.translatesAutoresizingMaskIntoConstraints = false

		let noteField = NSTextField(wrappingLabelWithString: "")
		noteField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		noteField.textColor = .secondaryLabelColor
		noteField.isSelectable = true
		noteField.translatesAutoresizingMaskIntoConstraints = false
		noteField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		let websiteButton = NSButton(title: "", target: self, action: #selector(openWebsite(_:)))
		websiteButton.isBordered = false
		websiteButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		websiteButton.contentTintColor = .linkColor
		websiteButton.translatesAutoresizingMaskIntoConstraints = false

		guard let accountContent = accountBox.contentView else {
			return
		}

		accountContent.addSubview(accountNameLabel)
		accountContent.addSubview(accountNameField)
		accountContent.addSubview(passwordLabel)
		accountContent.addSubview(passwordField)
		accountContent.addSubview(saslCheck)
		accountContent.addSubview(noteField)
		accountContent.addSubview(websiteButton)

		NSLayoutConstraint.activate([
			accountNameLabel.topAnchor.constraint(equalTo: accountContent.topAnchor, constant: 8),
			accountNameLabel.leadingAnchor.constraint(equalTo: accountContent.leadingAnchor, constant: 8),
			accountNameLabel.widthAnchor.constraint(equalToConstant: 110),
			accountNameField.leadingAnchor.constraint(equalTo: accountNameLabel.trailingAnchor, constant: 8),
			accountNameField.trailingAnchor.constraint(equalTo: accountContent.trailingAnchor, constant: -8),
			accountNameField.firstBaselineAnchor.constraint(equalTo: accountNameLabel.firstBaselineAnchor),
			passwordLabel.topAnchor.constraint(equalTo: accountNameField.bottomAnchor, constant: 8),
			passwordLabel.trailingAnchor.constraint(equalTo: accountNameLabel.trailingAnchor),
			passwordLabel.widthAnchor.constraint(equalTo: accountNameLabel.widthAnchor),
			passwordField.leadingAnchor.constraint(equalTo: accountNameField.leadingAnchor),
			passwordField.trailingAnchor.constraint(equalTo: accountNameField.trailingAnchor),
			passwordField.firstBaselineAnchor.constraint(equalTo: passwordLabel.firstBaselineAnchor),
			saslCheck.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 8),
			saslCheck.leadingAnchor.constraint(equalTo: accountNameField.leadingAnchor),
			noteField.topAnchor.constraint(equalTo: saslCheck.bottomAnchor, constant: 6),
			noteField.leadingAnchor.constraint(equalTo: accountNameField.leadingAnchor),
			noteField.trailingAnchor.constraint(equalTo: accountNameField.trailingAnchor),
			websiteButton.topAnchor.constraint(equalTo: noteField.bottomAnchor, constant: 2),
			websiteButton.leadingAnchor.constraint(equalTo: accountNameField.leadingAnchor),
			websiteButton.bottomAnchor.constraint(equalTo: accountContent.bottomAnchor, constant: -6),
		])

		detailView.addSubview(titleField)
		detailView.addSubview(badge)
		detailView.addSubview(addressLabel)
		detailView.addSubview(addressField)
		detailView.addSubview(portLabel)
		detailView.addSubview(portField)
		detailView.addSubview(securedCheck)
		detailView.addSubview(accountBox)

		NSLayoutConstraint.activate([
			titleField.topAnchor.constraint(equalTo: detailView.topAnchor),
			titleField.leadingAnchor.constraint(equalTo: detailView.leadingAnchor),
			badge.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 8),
			badge.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
			badge.trailingAnchor.constraint(lessThanOrEqualTo: detailView.trailingAnchor),
			addressLabel.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 10),
			addressLabel.leadingAnchor.constraint(equalTo: detailView.leadingAnchor),
			addressLabel.widthAnchor.constraint(equalToConstant: 122),
			addressField.leadingAnchor.constraint(equalTo: addressLabel.trailingAnchor, constant: 8),
			addressField.firstBaselineAnchor.constraint(equalTo: addressLabel.firstBaselineAnchor),
			portLabel.leadingAnchor.constraint(equalTo: addressField.trailingAnchor, constant: 12),
			portLabel.firstBaselineAnchor.constraint(equalTo: addressLabel.firstBaselineAnchor),
			portField.leadingAnchor.constraint(equalTo: portLabel.trailingAnchor, constant: 8),
			portField.widthAnchor.constraint(equalToConstant: 64),
			portField.trailingAnchor.constraint(equalTo: detailView.trailingAnchor),
			portField.firstBaselineAnchor.constraint(equalTo: addressLabel.firstBaselineAnchor),
			securedCheck.topAnchor.constraint(equalTo: addressField.bottomAnchor, constant: 8),
			securedCheck.leadingAnchor.constraint(equalTo: addressField.leadingAnchor),
			accountBox.topAnchor.constraint(equalTo: securedCheck.bottomAnchor, constant: 8),
			accountBox.leadingAnchor.constraint(equalTo: detailView.leadingAnchor),
			accountBox.trailingAnchor.constraint(equalTo: detailView.trailingAnchor),
			accountBox.bottomAnchor.constraint(lessThanOrEqualTo: detailView.bottomAnchor),
		])

		NSLayoutConstraint.activate([
			badge.widthAnchor.constraint(equalToConstant: badge.intrinsicContentSize.width + 12),
			badge.heightAnchor.constraint(equalToConstant: badge.intrinsicContentSize.height + 2),
		])

		view.addSubview(detailView)

		NSLayoutConstraint.activate([
			detailView.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
			detailView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			detailView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			detailView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])

		self.detailView = detailView
		detailTitleField = titleField
		registrationBadge = badge
		serverAddressField = addressField
		serverPortField = portField
		self.securedCheck = securedCheck
		self.accountBox = accountBox
		self.accountNameField = accountNameField
		accountPasswordField = passwordField
		self.saslCheck = saslCheck
		registrationNoteField = noteField
		self.websiteButton = websiteButton
	}

	// MARK: - Rows

	private func reloadRows() {
		let query = (searchField.stringValue as NSString).trim
		var rows: [NetworkPickerRow] = []

		if query.isEmpty {
			rows.append(NetworkPickerRow.groupRow(title: LocalizedKey("TDCOnboardingWindow[np1-gp]")))

			for network in networkList.popularNetworks {
				rows.append(NetworkPickerRow.networkRow(network))
			}

			rows.append(NetworkPickerRow.groupRow(title: LocalizedKey("TDCOnboardingWindow[np1-ga]")))

			for network in networkList.listOfNetworks {
				rows.append(NetworkPickerRow.networkRow(network))
			}
		} else {
			for network in networkList.listOfNetworks {
				if (network.networkName as NSString).containsIgnoringCase(query)
					|| (network.serverAddress as NSString).containsIgnoringCase(query)
					|| (network.networkDescription as NSString).containsIgnoringCase(query)
				{
					rows.append(NetworkPickerRow.networkRow(network))
				}
			}
		}

		rows.append(NetworkPickerRow.customRow())

		self.rows = rows
		tableView.reloadData()
		restoreSelectionInTable()
	}

	private func restoreSelectionInTable() {
		var rowToSelect = -1

		if customServerSelected {
			rowToSelect = rows.count - 1
		} else if let selectedNetwork {
			if let index = rows.firstIndex(where: { $0.kind == .network && $0.network === selectedNetwork }) {
				rowToSelect = index
			}
		}

		if rowToSelect < 0 {
			tableView.deselectAll(nil)
		} else {
			tableView.selectRowIndexes(IndexSet(integer: rowToSelect), byExtendingSelection: false)
			tableView.scrollRowToVisible(rowToSelect)
		}
	}

	// MARK: - Selection

	@objc public var hasSelection: Bool {
		selectedNetwork != nil || customServerSelected
	}

	@objc(selectNetwork:)
	public func selectNetwork(_ network: Network) {
		selectedNetwork = network
		customServerSelected = false
		accountNameEdited = false

		populateDetailFromSelection()
		restoreSelectionInTable()
		informDelegateSelectionChanged()
	}

	@objc(selectServerAddress:port:secured:)
	public func selectServerAddress(_ serverAddress: String, port: UInt16, secured: Bool) {
		if let network = networkList.network(withServerAddress: serverAddress)
			?? networkList.network(named: serverAddress)
		{
			selectNetwork(network)
			return
		}

		selectedNetwork = nil
		customServerSelected = true
		accountNameEdited = false

		populateDetailFromSelection()

		serverAddressField.stringValue = serverAddress

		if port > 0 {
			serverPortField.integerValue = Int(port)
		}

		securedCheck.state = secured ? .on : .off

		restoreSelectionInTable()
		informDelegateSelectionChanged()
	}

	@objc public func clearSelection() {
		selectedNetwork = nil
		customServerSelected = false
		accountNameEdited = false

		populateDetailFromSelection()
		restoreSelectionInTable()
		informDelegateSelectionChanged()
	}

	private func selectRow(at index: Int) {
		if index < 0 || index >= rows.count {
			selectedNetwork = nil
			customServerSelected = false
		} else {
			let row = rows[index]

			switch row.kind {
			case .network:
				if row.network === selectedNetwork {
					return
				}

				selectedNetwork = row.network
				customServerSelected = false

			case .custom:
				if customServerSelected {
					return
				}

				selectedNetwork = nil
				customServerSelected = true

			default:
				return
			}
		}

		accountNameEdited = false
		populateDetailFromSelection()
		informDelegateSelectionChanged()
	}

	private func populateDetailFromSelection() {
		if let network = selectedNetwork {
			detailTitleField.stringValue = network.networkName
			serverAddressField.stringValue = network.serverAddress
			serverPortField.integerValue = Int(network.serverPort)
			securedCheck.state = network.prefersSecuredConnection ? .on : .off
			saslCheck.state = network.saslSupported ? .on : .off
			saslCheck.isEnabled = network.saslSupported
			registrationNoteField.stringValue = network.registrationNote ?? ""
			registrationBadge.isHidden = network.registration != .required

			if let website = network.website, website.isEmpty == false {
				websiteButton.title = website
				websiteButton.isHidden = false
			} else {
				websiteButton.title = ""
				websiteButton.isHidden = true
			}
		} else {
			detailTitleField.stringValue = LocalizedKey("TDCOnboardingWindow[np1-cs]")
			serverAddressField.stringValue = ""
			serverPortField.stringValue = LocalizedKey("TDCOnboardingWindow[np1-pp]")
			securedCheck.state = .on
			saslCheck.state = .on
			saslCheck.isEnabled = true
			registrationNoteField.stringValue = ""
			registrationBadge.isHidden = true
			websiteButton.title = ""
			websiteButton.isHidden = true
		}

		accountNameField.stringValue = defaultNickname ?? ""
		accountPasswordField.stringValue = ""

		updateDetailView()
	}

	private func updateDetailView() {
		detailView.isHidden = hasSelection == false

		let network = selectedNetwork
		/* A custom server may have services; the group stays available. */
		let showAccount = network == nil || network?.accountFieldsApply == true
		accountBox.isHidden = showAccount == false
	}

	private func informDelegateSelectionChanged() {
		let selector = NSSelectorFromString("networkPickerSelectionDidChange:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}

	// MARK: - Values

	@objc public var serverAddress: String {
		(serverAddressField.stringValue as NSString).trim.lowercased()
	}

	@objc public var serverPort: UInt16 {
		let port = serverPortField.integerValue

		if port <= 0 || port > Int(UInt16.max) {
			return 0
		}

		return UInt16(port)
	}

	@objc public var prefersSecuredConnection: Bool {
		securedCheck.state == .on
	}

	@objc public var accountName: String {
		if accountBox.isHidden {
			return ""
		}

		return (accountNameField.stringValue as NSString).trim
	}

	@objc public var accountPassword: String {
		if accountBox.isHidden {
			return ""
		}

		return accountPasswordField.stringValue
	}

	@objc public var usesSASL: Bool {
		if accountBox.isHidden {
			return false
		}

		return saslCheck.state == .on && accountPassword.isEmpty == false
	}

	@objc public var suggestedChannels: [String] {
		selectedNetwork?.suggestedChannels ?? []
	}

	@objc(validateWithError:)
	public func validateWithError(_ errorDescription: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
		if hasSelection == false {
			if let errorDescription {
				errorDescription.pointee = LocalizedKey("TDCOnboardingWindow[np1-e1]") as NSString
			}

			return false
		}

		if (serverAddress as NSString).isValidInternetAddress == false {
			if let errorDescription {
				errorDescription.pointee = LocalizedKey("CommonErrors[yyx-l3]") as NSString
			}

			return false
		}

		if serverPort == 0 {
			if let errorDescription {
				errorDescription.pointee = LocalizedKey("TDCOnboardingWindow[np1-e2]") as NSString
			}

			return false
		}

		return true
	}

	@objc public func clientConfig() -> IRCClientConfigMutable? {
		if validateWithError(nil) == false {
			return nil
		}

		let config = IRCClientConfigMutable()

		if let network = selectedNetwork {
			config.connectionName = network.networkName
		} else {
			config.connectionName = serverAddress
		}

		let server = IRCServerMutable()
		server.serverAddress = serverAddress
		server.serverPort = serverPort
		server.prefersSecuredConnection = prefersSecuredConnection

		config.serverList = [server.copy() as! IRCServer]

		let password = accountPassword

		if password.isEmpty == false {
			/* The password is handed to NickServ when it asks and to SASL when
			 the server offers it. SASL authenticates as the username, so the
			 account name is only applied as the username when SASL is wanted. */
			config.nicknamePassword = password

			let name = accountName

			if usesSASL, name.isEmpty == false {
				config.username = name
			}
		}

		return config
	}

	// MARK: - Actions

	@objc public func focusSearchField() {
		view.window?.makeFirstResponder(searchField)
	}

	@objc private func fieldChanged(_: Any?) {
		informDelegateSelectionChanged()
	}

	@objc private func openWebsite(_: Any?) {
		guard let website = selectedNetwork?.website, website.isEmpty == false,
			let url = URL(string: website)
		else {
			return
		}

		NSWorkspace.shared.open(url)
	}

	@objc private func tableViewDoubleClicked(_: Any?) {
		if hasSelection == false {
			return
		}

		let selector = NSSelectorFromString("networkPickerDidConfirmSelection:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}

	// MARK: - Text Field Delegate

	public func controlTextDidChange(_ notification: Notification) {
		guard let object = notification.object as? AnyObject else {
			return
		}

		if object === searchField {
			reloadRows()
			return
		}

		if object === accountNameField {
			accountNameEdited = true
		}

		informDelegateSelectionChanged()
	}

	public func control(
		_ control: NSControl,
		textView _: NSTextView,
		doCommandBy commandSelector: Selector
	) -> Bool {
		if control !== searchField {
			return false
		}

		/* Arrow keys in the search field move the list selection. */
		if commandSelector == #selector(moveDown(_:)) {
			moveListSelection(by: 1)
			return true
		}

		if commandSelector == #selector(moveUp(_:)) {
			moveListSelection(by: -1)
			return true
		}

		if commandSelector == #selector(insertNewline(_:)) {
			if hasSelection == false {
				moveListSelection(by: 1)
			}

			return false
		}

		return false
	}

	private func moveListSelection(by delta: Int) {
		let row = tableView.selectedRow
		let count = rows.count
		var next = row + delta

		while next >= 0, next < count {
			if rows[next].kind == .group {
				next += delta
				continue
			}

			tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
			tableView.scrollRowToVisible(next)
			return
		}
	}

	// MARK: - Table View

	public func numberOfRows(in _: NSTableView) -> Int {
		rows.count
	}

	public func tableView(_: NSTableView, isGroupRow row: Int) -> Bool {
		rows[row].kind == .group
	}

	public func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
		rows[row].kind != .group
	}

	public func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
		rows[row].kind == .group ? 22 : 38
	}

	public func tableView(
		_ tableView: NSTableView,
		viewFor _: NSTableColumn?,
		row: Int
	) -> NSView? {
		let rowObject = rows[row]

		if rowObject.kind == .group {
			var cell = tableView.makeView(withIdentifier: groupCellIdentifier, owner: self) as? NSTableCellView

			if cell == nil {
				let newCell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
				newCell.identifier = groupCellIdentifier

				let label = NSTextField(labelWithString: "")
				label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
				label.textColor = .secondaryLabelColor
				label.translatesAutoresizingMaskIntoConstraints = false

				newCell.addSubview(label)

				NSLayoutConstraint.activate([
					label.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 4),
					label.centerYAnchor.constraint(equalTo: newCell.centerYAnchor),
				])

				newCell.textField = label
				cell = newCell
			}

			cell?.textField?.stringValue = rowObject.title ?? ""
			return cell
		}

		var cell = tableView.makeView(withIdentifier: networkCellIdentifier, owner: self) as? NetworkPickerCellView

		if cell == nil {
			let newCell = NetworkPickerCellView(frame: NSRect(x: 0, y: 0, width: 200, height: 38))
			newCell.identifier = networkCellIdentifier
			cell = newCell
		}

		if let network = rowObject.network {
			cell?.textField?.stringValue = network.networkName
			cell?.descriptionField.stringValue = network.networkDescription
			cell?.lockImageView.isHidden = network.prefersSecuredConnection == false
			cell?.toolTip = network.serverAddress
		} else {
			cell?.textField?.stringValue = rowObject.title ?? ""
			cell?.descriptionField.stringValue = LocalizedKey("TDCOnboardingWindow[np1-cd]")
			cell?.lockImageView.isHidden = true
			cell?.toolTip = nil
		}

		return cell
	}

	public func tableViewSelectionDidChange(_: Notification) {
		selectRow(at: tableView.selectedRow)
	}
}
