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

	static func groupRow(title: String) -> NetworkPickerRow {
		let row = NetworkPickerRow()
		row.kind = .group
		row.title = title
		return row
	}

	static func networkRow(_ network: Network) -> NetworkPickerRow {
		let row = NetworkPickerRow()
		row.kind = .network
		row.network = network
		row.title = network.networkName
		return row
	}

	static func customRow() -> NetworkPickerRow {
		let row = NetworkPickerRow()
		row.kind = .custom
		row.title = OnboardingStrings.NetworkPicker.customServerTitle
		return row
	}
}

// MARK: - Cell View

/** Name on the first line, description on the second, and a lock on the
 trailing edge when the network prefers TLS. */
private final class NetworkPickerCellView: NSTableCellView {
	var descriptionField: NSTextField!
	var lockImageView: NSImageView!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		prepareInitialState()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
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
				accessibilityDescription: OnboardingStrings.NetworkPicker.secureConnectionAccessibilityLabel
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

/// What `NetworkPickerViewController` reports back.
@MainActor
public protocol NetworkPickerViewControllerDelegate: AnyObject {
	func networkPickerSelectionDidChange(_ sender: NetworkPickerViewController)
	func networkPickerDidConfirmSelection(_ sender: NetworkPickerViewController)
}

@objc(TDCNetworkPickerViewController)
@MainActor
public final class NetworkPickerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
	NSSearchFieldDelegate, NSTextFieldDelegate
{
	public weak var delegate: (any NetworkPickerViewControllerDelegate)?

	@objc public private(set) var networkList: NetworkList
	@objc public private(set) var selectedNetwork: Network?
	@objc public private(set) var customServerSelected = false

	private var rows: [NetworkPickerRow] = []
	private var searchField: NSSearchField!
	private var scrollView: NSScrollView!
	private var tableView: NSTableView!
	private var detailView: NetworkPickerDetailView!
	private var accountNameEdited = false
	private var defaultNicknameStorage: String?

	@objc public var defaultNickname: String? {
		get { defaultNicknameStorage }
		set {
			defaultNicknameStorage = newValue

			if accountNameEdited == false, let detailView {
				detailView.updateDefaultNickname(newValue)
			}
		}
	}

	@objc public init() {
		networkList = NetworkList()
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
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
		populateDetailFromSelection()
	}

	private func buildListViews() {
		let searchField = NSSearchField()
		searchField.placeholderString = OnboardingStrings.NetworkPicker.searchPlaceholder
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
		tableView.setAccessibilityLabel(OnboardingStrings.NetworkPicker.accessibilityLabel)

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

	private func buildDetailViews() {
		let detailView = NetworkPickerDetailView(
			fieldDelegate: self,
			actionTarget: self,
			fieldChangedAction: #selector(fieldChanged(_:)),
			openWebsiteAction: #selector(openWebsite(_:))
		)

		view.addSubview(detailView)

		NSLayoutConstraint.activate([
			detailView.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
			detailView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			detailView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			detailView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])

		self.detailView = detailView
	}

	// MARK: - Rows

	private func reloadRows() {
		let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		var rows: [NetworkPickerRow] = []

		if query.isEmpty {
			rows.append(NetworkPickerRow.groupRow(title: OnboardingStrings.NetworkPicker.popularGroup))

			for network in networkList.popularNetworks {
				rows.append(NetworkPickerRow.networkRow(network))
			}

			rows.append(NetworkPickerRow.groupRow(title: OnboardingStrings.NetworkPicker.allNetworksGroup))

			for network in networkList.listOfNetworks {
				rows.append(NetworkPickerRow.networkRow(network))
			}
		} else {
			for network in networkList.listOfNetworks {
				if network.networkName.localizedCaseInsensitiveContains(query)
					|| network.serverAddress.localizedCaseInsensitiveContains(query)
					|| network.networkDescription.localizedCaseInsensitiveContains(query)
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
		detailView.displayCustomServer(address: serverAddress, port: port, secured: secured)

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
		detailView.display(
			network: selectedNetwork,
			customServerSelected: customServerSelected,
			defaultNickname: defaultNickname
		)
	}

	private func informDelegateSelectionChanged() {
		delegate?.networkPickerSelectionDidChange(self)
	}

	// MARK: - Values

	@objc public var serverAddress: String {
		detailView.serverAddress
	}

	@objc public var serverPort: UInt16 {
		detailView.serverPort
	}

	@objc public var prefersSecuredConnection: Bool {
		detailView.prefersSecuredConnection
	}

	@objc public var accountName: String {
		detailView.accountName
	}

	@objc public var accountPassword: String {
		detailView.accountPassword
	}

	@objc public var usesSASL: Bool {
		detailView.usesSASL
	}

	@objc public var suggestedChannels: [String] {
		selectedNetwork?.suggestedChannels ?? []
	}

	@objc(validateWithError:)
	public func validateWithError(_ errorDescription: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
		if hasSelection == false {
			if let errorDescription {
				errorDescription.pointee = OnboardingStrings.NetworkPicker.missingServer as NSString
			}

			return false
		}

		if (serverAddress as NSString).isValidInternetAddress == false {
			if let errorDescription {
				errorDescription.pointee = CommonValidationStrings.invalidServerAddress as NSString
			}

			return false
		}

		if serverPort == 0 {
			if let errorDescription {
				errorDescription.pointee = OnboardingStrings.NetworkPicker.invalidPort as NSString
			}

			return false
		}

		return true
	}

	public func clientConfig() -> ClientConfig? {
		if validateWithError(nil) == false {
			return nil
		}

		var config = ClientConfig()

		if let network = selectedNetwork {
			config.connectionName = network.networkName
		} else {
			config.connectionName = serverAddress
		}

		config.serverList = [
			Server(
				serverAddress: serverAddress,
				serverPort: serverPort,
				prefersSecuredConnection: prefersSecuredConnection
			),
		]

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

		delegate?.networkPickerDidConfirmSelection(self)
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

		if detailView.ownsAccountNameField(object) {
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
			cell?.descriptionField.stringValue = OnboardingStrings.NetworkPicker.customServerDescription
			cell?.lockImageView.isHidden = true
			cell?.toolTip = nil
		}

		return cell
	}

	public func tableViewSelectionDidChange(_: Notification) {
		selectRow(at: tableView.selectedRow)
	}
}
