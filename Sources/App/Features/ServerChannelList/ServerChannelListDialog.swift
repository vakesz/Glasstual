/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions

public nonisolated struct ServerChannelListDialogEntry: Identifiable, Hashable, Sendable { // nonisolated: value
	public let id = UUID()
	public var channelName = ""
	public var channelMemberCount = 0
	/// The topic as the server sent it, control codes and all. The formatted
	/// version is built when a cell draws it, so the entry stays a value.
	public var channelTopicUnformatted = ""

	/// Does the search field's text pick this entry out?
	///
	/// The array controller asked this through a predicate that existed only in
	/// the nib — `channelName contains[c] $value OR channelTopicUnformatted
	/// contains[c] $value` — so nothing in Swift could see it, let alone test
	/// it. `contains[c]` is a plain case-insensitive substring search, and an
	/// empty needle matches everything.
	public func matches(searchString: String) -> Bool {
		guard searchString.isEmpty == false else {
			return true
		}

		return channelName.range(of: searchString, options: .caseInsensitive) != nil
			|| channelTopicUnformatted.range(of: searchString, options: .caseInsensitive) != nil
	}

	/// The rows the table draws: the entries the search keeps, in the order the
	/// column header asks for.
	///
	/// Pure, so what the dialog shows can be checked without building a window.
	public static func rows(
		from entries: [ServerChannelListDialogEntry],
		matching searchString: String,
		sortedBy sortKey: String?,
		ascending: Bool
	) -> [ServerChannelListDialogEntry] {
		let matching = entries.filter { $0.matches(searchString: searchString) }

		guard let key = sortKey.flatMap(ServerChannelListSortKey.init(rawValue:)) else {
			return matching
		}

		switch key {
		case .channelName:
			return matching.sorted { ordered($0.channelName, $1.channelName, ascending) }
		case .channelMemberCount:
			return matching.sorted { ordered($0.channelMemberCount, $1.channelMemberCount, ascending) }
		case .channelTopicUnformatted:
			/* The topic column draws the formatted topic but sorts on the plain
			 one, case-insensitively, exactly as its nib prototype asked. */
			return matching.sorted {
				let result = $0.channelTopicUnformatted
					.caseInsensitiveCompare($1.channelTopicUnformatted)

				return ascending ? result == .orderedAscending : result == .orderedDescending
			}
		}
	}
}

private nonisolated func ordered<Value: Comparable>( // nonisolated: pure
	_ lhs: Value,
	_ rhs: Value,
	_ ascending: Bool
) -> Bool {
	ascending ? lhs < rhs : lhs > rhs
}

private nonisolated enum ServerChannelListSection: Hashable, Sendable { // nonisolated: value
	case entries
}

/// The table's columns, named the way the nib identifies them.
private nonisolated enum ServerChannelListColumn: String { // nonisolated: value
	case channelName
	case channelMemberCount
	case channelTopic
}

/// The keys the column headers sort by. The topic column is the odd one: it
/// draws `channelTopic` and sorts on `channelTopicUnformatted`.
private nonisolated enum ServerChannelListSortKey: String { // nonisolated: value
	case channelName
	case channelMemberCount
	case channelTopicUnformatted
}

private typealias ServerChannelListDataSource =
	NSTableViewDiffableDataSource<ServerChannelListSection, ServerChannelListDialogEntry.ID>

/// What `ServerChannelListDialog` reports back.
@MainActor
public protocol ServerChannelListDialogDelegate: AnyObject {
	func serverChannelListDialogOnUpdate(_ sender: ServerChannelListDialog)
	func serverChannelListDialog(_ sender: ServerChannelListDialog, joinChannels channels: [String])
	func serverChannelDialogWillClose(_ sender: ServerChannelListDialog)
}

@objc(TDCServerChannelListDialog)
@MainActor
public final class ServerChannelListDialog: WindowBase, TDCClientPrototype {
	var listDelegate: (any ServerChannelListDialogDelegate)? {
		delegate as? any ServerChannelListDialogDelegate
	}

	@objc public private(set) var client: IRCClient!
	@objc public private(set) var clientId: String?
	@objc public var contentAlreadyReceived = false

	@IBOutlet private var updateButton: NSButton!
	@IBOutlet private var searchTextField: NSSearchField!
	@IBOutlet private var networkNameTextField: NSTextField!
	@IBOutlet private var channelListTable: BasicTableView!

	private var isWaitingForWrites = false
	private var queuedWrites: [ServerChannelListDialogEntry] = []
	private var minimumUserCountLabel: NSTextField?
	private var minimumUserCountTextField: NSTextField?

	/// Every channel the server has named, whether the search shows it or not.
	private var allEntries: [ServerChannelListDialogEntry] = []
	/// What the table draws: `allEntries` filtered and sorted.
	private var displayedEntries: [ServerChannelListDialogEntry] = []
	private var displayedEntriesByID: [ServerChannelListDialogEntry.ID: ServerChannelListDialogEntry] = [:]
	private var channelListDataSource: ServerChannelListDataSource?
	private var searchString = ""

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(client:)")
	}

	@objc(initWithClient:)
	public init(client: IRCClient) {
		super.init()

		self.client = client
		clientId = client.uniqueIdentifier

		prepareInitialState()
	}

	@objc public var serverSideListArguments: String? {
		Self.listArguments(
			forMinimumUserCount: UInt(minimumUserCountTextField?.integerValue ?? 0),
			pattern: searchTextField.stringValue,
			supportedTokens: client.supportInfo.extendedListTokens
		)
	}

	@objc(listArgumentsForMinimumUserCount:pattern:supportedTokens:)
	public static func listArguments(
		forMinimumUserCount minimumUserCount: UInt,
		pattern: String?,
		supportedTokens: [String]
	) -> String? {
		var conditions: [String] = []

		if minimumUserCount > 0, supportedTokens.contains("U") {
			conditions.append(">\(minimumUserCount - 1)")
		}

		let trimmedPattern = pattern?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

		if trimmedPattern.isEmpty == false, supportedTokens.contains("M") {
			let invalidCharacters = CharacterSet(charactersIn: ", ")
			if trimmedPattern.rangeOfCharacter(from: invalidCharacters) == nil {
				var patternValue = trimmedPattern

				if patternValue.contains("*") == false, patternValue.contains("?") == false {
					patternValue = "*\(patternValue)*"
				}

				conditions.append(patternValue)
			}
		}

		if conditions.isEmpty {
			return nil
		}

		return conditions.joined(separator: ",")
	}

	override public func show() {
		window.ce_restoreState(for: Self.self)
		super.show()
	}

	@objc public func clear() {
		allEntries.removeAll()

		applyEntries()
	}

	@objc public func addChannel(_ channel: String, count: UInt, topic: String?) {
		var newEntry = ServerChannelListDialogEntry()
		newEntry.channelName = channel
		newEntry.channelMemberCount = Int(count)
		newEntry.channelTopicUnformatted = topic ?? ""

		/* This type is @MainActor, so no synchronisation is needed. What used to
		 be here boxed the Swift Array into a fresh __SwiftValue on every call and
		 so locked nothing at all. */
		queuedWrites.append(newEntry)

		if isWaitingForWrites == false {
			isWaitingForWrites = true
			textual_performSelectorInCommonModes(#selector(queuedWritesTimer), with: nil, afterDelay: 1.0)
		}
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCServerChannelListDialog", owner: self, topLevelObjects: nil)

		queuedWrites = []

		channelListDataSource = makeDataSource()
		channelListTable.dataSource = channelListDataSource
		channelListTable.delegate = self
		channelListTable.doubleAction = #selector(onJoin(_:))
		channelListTable.sortDescriptors = [
			NSSortDescriptor(key: ServerChannelListSortKey.channelMemberCount.rawValue, ascending: false),
		]

		/* The search field used to filter through a predicate bound to the array
		 controller. Its action covers the cancel button, which does not always
		 reach the text-editing delegate. */
		searchTextField.target = self
		searchTextField.action = #selector(searchStringChanged(_:))

		networkNameTextField.stringValue = ServerChannelListStrings.heading(networkName: client.networkNameAlt)
		prepareMinimumUserCountControls()

		applyEntries()
	}

	private func makeDataSource() -> ServerChannelListDataSource {
		ServerChannelListDataSource(tableView: channelListTable) { [weak self] tableView, column, _, entryID in
			let view = tableView.makeView(withIdentifier: column.identifier, owner: self)

			guard let cell = view as? NSTableCellView, let field = cell.textField else {
				return view ?? NSView()
			}

			guard let entry = self?.displayedEntriesByID[entryID] else {
				field.stringValue = ""

				return cell
			}

			switch ServerChannelListColumn(rawValue: column.identifier.rawValue) {
			case .channelName:
				field.stringValue = entry.channelName
			case .channelMemberCount:
				field.stringValue = String(entry.channelMemberCount)
			case .channelTopic:
				field.attributedStringValue = Self.formattedTopic(entry.channelTopicUnformatted)
			case nil:
				field.stringValue = ""
			}

			return cell
		}
	}

	/// The topic with its IRC control codes rendered. Built per drawn cell now
	/// that the entry is a value; only the visible rows ever pay for it.
	private static func formattedTopic(_ topic: String) -> NSAttributedString {
		guard topic.isEmpty == false else {
			return NSAttributedString()
		}

		return (topic as NSString).attributedString(
			withIRCFormatting: NSTableView.preferredGlobalTableViewFont(),
			preferredFontColor: .controlTextColor
		) ?? NSAttributedString()
	}

	/// Filters and sorts what has arrived, and hands the rows to the table.
	private func applyEntries() {
		guard let channelListDataSource else {
			return
		}

		let descriptor = channelListTable.sortDescriptors.first

		displayedEntries = ServerChannelListDialogEntry.rows(
			from: allEntries,
			matching: searchString,
			sortedBy: descriptor?.key,
			ascending: descriptor?.ascending ?? true
		)

		displayedEntriesByID = Dictionary(
			displayedEntries.map { ($0.id, $0) },
			uniquingKeysWith: { _, latest in latest }
		)

		var snapshot =
			NSDiffableDataSourceSnapshot<ServerChannelListSection, ServerChannelListDialogEntry.ID>()
		snapshot.appendSections([.entries])
		snapshot.appendItems(displayedEntries.map(\.id), toSection: .entries)
		channelListDataSource.apply(snapshot, animatingDifferences: false)

		updateDialogTitle()
	}

	@objc private func searchStringChanged(_: Any?) {
		updateSearchString()
	}

	private func updateSearchString() {
		let newValue = searchTextField.stringValue

		guard newValue != searchString else {
			return
		}

		searchString = newValue

		applyEntries()
	}

	private func prepareMinimumUserCountControls() {
		guard client.supportInfo.extendedListSupportsToken("U") else {
			return
		}

		guard let contentView = window.contentView else {
			return
		}

		let label = NSTextField(labelWithString: ServerChannelListStrings.minimumUserCountLabel)
		label.translatesAutoresizingMaskIntoConstraints = false

		let formatter = NumberFormatter()
		formatter.numberStyle = .none
		formatter.minimum = 0
		formatter.maximum = 999_999
		formatter.allowsFloats = false

		let textField = NSTextField(string: "")
		textField.translatesAutoresizingMaskIntoConstraints = false
		textField.formatter = formatter
		textField.placeholderString = "0"
		textField.alignment = .right
		textField.toolTip = ServerChannelListStrings.minimumUserCountHint
		textField.setAccessibilityLabel(ServerChannelListStrings.minimumUserCountLabel)

		contentView.addSubview(label)
		contentView.addSubview(textField)

		NSLayoutConstraint.activate([
			textField.widthAnchor.constraint(equalToConstant: 60),
			textField.trailingAnchor.constraint(equalTo: searchTextField.leadingAnchor, constant: -12),
			textField.centerYAnchor.constraint(equalTo: searchTextField.centerYAnchor),
			label.trailingAnchor.constraint(equalTo: textField.leadingAnchor, constant: -6),
			label.firstBaselineAnchor.constraint(equalTo: textField.firstBaselineAnchor),
			label.leadingAnchor.constraint(
				greaterThanOrEqualTo: networkNameTextField.trailingAnchor,
				constant: 20
			),
		])

		minimumUserCountLabel = label
		minimumUserCountTextField = textField
	}

	@objc private func queuedWritesTimer() {
		isWaitingForWrites = false
		writeQueuedWrites()
	}

	/// Moves everything the server has named into the list.
	///
	/// The queue used to be drained through the filter, and anything the search
	/// rejected stayed queued — so a channel could sit unseen until the search
	/// field happened to be cleared. The filter is applied to the rows now
	/// rather than to the arrivals, so the queue always empties.
	private func writeQueuedWrites() {
		guard queuedWrites.isEmpty == false else {
			return
		}

		allEntries.append(contentsOf: queuedWrites)
		queuedWrites.removeAll()

		applyEntries()
	}

	private func updateDialogTitle() {
		window.title = ServerChannelListStrings.windowTitle(publicChannelCount: displayedEntries.count)
	}

	@IBAction private func onClose(_: Any?) {
		close()
	}

	@IBAction private func onUpdate(_: Any?) {
		clear()

		listDelegate?.serverChannelListDialogOnUpdate(self)
	}

	@IBAction private func onJoinChannels(_ sender: Any?) {
		onJoin(sender)
	}

	@objc private func onJoin(_ sender: Any?) {
		let channelNames = channelListTable.selectedRowIndexes.compactMap { row in
			displayedEntries.indices.contains(row) ? displayedEntries[row].channelName : nil
		}

		listDelegate?.serverChannelListDialog(self, joinChannels: channelNames)

		channelListTable.deselectAll(sender)
	}
}

extension ServerChannelListDialog: NSControlTextEditingDelegate {
	public func controlTextDidChange(_ obj: Notification) {
		guard obj.object as AnyObject? === searchTextField else {
			return
		}

		updateSearchString()
	}
}

extension ServerChannelListDialog: NSTableViewDelegate {
	public func tableView(
		_ tableView: NSTableView,
		selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet
	) -> IndexSet {
		tableView.selectionIndexes(
			forProposedSelection: proposedSelectionIndexes,
			maximumCount: 8
		)
	}

	/// Re-sorts and re-applies. The array controller used to do this through a
	/// `sortDescriptors` binding.
	public func tableView(_: NSTableView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
		applyEntries()
	}
}

extension ServerChannelListDialog: NSWindowDelegate {
	public func windowWillClose(_: Notification) {
		textual_cancelPerformRequests()
		channelListTable.dataSource = nil
		channelListTable.delegate = nil
		channelListDataSource = nil
		window.ce_saveState(for: Self.self)

		listDelegate?.serverChannelDialogWillClose(self)
	}
}
