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

/// What `ChannelBanListSheet` reports back.
@MainActor
public protocol ChannelBanListSheetDelegate: AnyObject {
	func channelBanListSheetOnUpdate(_ sender: ChannelBanListSheet)
	func channelBanListSheetWillClose(_ sender: ChannelBanListSheet)
}

@objc(TDCChannelBanListSheetEntryType)
public enum ChannelBanListEntryType: UInt {
	case ban = 0
	case banException
	case inviteException
	case quiet

	/** Spelled out rather than mapped by raw value: the two enums are declared
	 in different modules and reordering either one would silently point the
	 sheet at the wrong mode. */
	var supportListType: IRCISupportInfoListType {
		switch self {
		case .ban: .ban
		case .banException: .banException
		case .inviteException: .inviteException
		case .quiet: .quiet
		}
	}
}

public nonisolated struct ChannelBanListSheetEntry: Identifiable, Hashable, Sendable { // nonisolated: value
	public let id = UUID()
	public var entryMask = ""
	public var entryMaskDescription: String?
	public var entryAuthor = ""
	public var entryCreationDate: Date?

	public var entryCreationDateString: String {
		guard let entryCreationDate else {
			return ApplicationStrings.unknownValue
		}

		return formatDateLongStyle(entryCreationDate, true) ?? ApplicationStrings.unknownValue
	}
}

private nonisolated enum ChannelBanListSection: Hashable, Sendable { // nonisolated: value
	case entries
}

/// The table's columns, named the way the nib identifies them. The sort keys
/// the header sends back are these same names.
private nonisolated enum ChannelBanListColumn: String { // nonisolated: value
	case mask = "entryMask"
	case author = "entryAuthor"
	case creationDate = "entryCreationDate"
}

private typealias ChannelBanListDataSource =
	NSTableViewDiffableDataSource<ChannelBanListSection, ChannelBanListSheetEntry.ID>

@objc(TDCChannelBanListSheet)
@MainActor
public final class ChannelBanListSheet: SheetBase, TDCChannelPrototype {
	@objc public private(set) var client: IRCClient!
	@objc public private(set) var channel: IRCChannel!
	@objc public private(set) var clientId: String?
	@objc public private(set) var channelId: String?
	@objc public private(set) var entryType: ChannelBanListEntryType = .ban
	@objc public private(set) var listOfChanges: [String]?
	@objc public var contentAlreadyReceived = false

	@IBOutlet private var headerTitleTextField: NSTextField!
	@IBOutlet private var entryTable: BasicTableView!
	@IBOutlet private var entryCountTextField: NSTextField!

	/// The entries the server has sent, in the order the table draws them.
	private var tableEntries: [ChannelBanListSheetEntry] = []
	private var entryDataSource: ChannelBanListDataSource?

	@objc(initWithEntryType:inChannel:)
	public init?(entryType: ChannelBanListEntryType, inChannel channel: IRCChannel) {
		guard Self.channel(channel, supportsEntryType: entryType) else {
			return nil
		}

		super.init(window: nil)

		self.entryType = entryType
		client = channel.associatedClient
		clientId = channel.associatedClient!.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier

		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCChannelBanListSheet", owner: self, topLevelObjects: nil)

		entryDataSource = makeDataSource()
		entryTable.dataSource = entryDataSource
		entryTable.delegate = self
		entryTable.sortDescriptors = [
			NSSortDescriptor(key: ChannelBanListColumn.creationDate.rawValue, ascending: false),
		]

		headerTitleTextField.stringValue = ChannelAccessListStrings.heading(
			for: entryType,
			channelName: channel.name
		)

		applyEntries()
	}

	private func makeDataSource() -> ChannelBanListDataSource {
		ChannelBanListDataSource(tableView: entryTable) { [weak self] tableView, column, _, entryID in
			let view = tableView.makeView(withIdentifier: column.identifier, owner: self)

			guard let cell = view as? NSTableCellView, let field = cell.textField else {
				return view ?? NSView()
			}

			guard let entry = self?.entry(withID: entryID) else {
				field.stringValue = ""

				return cell
			}

			switch ChannelBanListColumn(rawValue: column.identifier.rawValue) {
			case .mask:
				field.stringValue = entry.entryMask
				field.toolTip = entry.entryMaskDescription
			case .author:
				field.stringValue = entry.entryAuthor
			case .creationDate:
				field.stringValue = entry.entryCreationDateString
			case nil:
				field.stringValue = ""
			}

			return cell
		}
	}

	private func entry(withID id: ChannelBanListSheetEntry.ID) -> ChannelBanListSheetEntry? {
		tableEntries.first { $0.id == id }
	}

	/// Sorts the entries the way the header asks and hands them to the table.
	private func applyEntries() {
		guard let entryDataSource else {
			return
		}

		sortEntries()

		var snapshot = NSDiffableDataSourceSnapshot<ChannelBanListSection, ChannelBanListSheetEntry.ID>()
		snapshot.appendSections([.entries])
		snapshot.appendItems(tableEntries.map(\.id), toSection: .entries)
		entryDataSource.apply(snapshot, animatingDifferences: false)

		entryCountTextField?.stringValue = entryCountDescription
	}

	private func sortEntries() {
		guard let descriptor = entryTable.sortDescriptors.first,
		      let column = descriptor.key.flatMap(ChannelBanListColumn.init(rawValue:))
		else {
			return
		}

		let ascending = descriptor.ascending

		switch column {
		case .mask:
			tableEntries.sort { ordered($0.entryMask, $1.entryMask, ascending) }
		case .author:
			tableEntries.sort { ordered($0.entryAuthor, $1.entryAuthor, ascending) }
		case .creationDate:
			tableEntries.sort {
				ordered(
					$0.entryCreationDate ?? .distantPast,
					$1.entryCreationDate ?? .distantPast,
					ascending
				)
			}
		}
	}

	private func ordered<Value: Comparable>(_ lhs: Value, _ rhs: Value, _ ascending: Bool) -> Bool {
		ascending ? lhs < rhs : lhs > rhs
	}

	@objc public func start() {
		startSheet()
	}

	@objc public func clear() {
		tableEntries.removeAll()

		applyEntries()
	}

	@objc(addEntry:setBy:creationDate:)
	public func addEntry(
		_ entryMask: String,
		setBy entryAuthor: String?,
		creationDate entryCreationDate: Date?
	) {
		var newEntry = ChannelBanListSheetEntry()
		newEntry.entryMask = entryMask
		newEntry.entryMaskDescription = client.supportInfo.descriptionForExtendedBanMask(entryMask)
		newEntry.entryAuthor = entryAuthor ?? ApplicationStrings.unknownValue
		newEntry.entryCreationDate = entryCreationDate

		tableEntries.append(newEntry)

		applyEntries()
	}

	public var entryCount: Int {
		tableEntries.count
	}

	public var entryCountDescription: String {
		let entryCount = tableEntries.count
		let maximumEntries = ChannelModeSymbol(modeSymbol)
			.map { Int(client.supportInfo.maximumListEntries(forModeSymbol: $0)) } ?? 0

		return ChannelAccessListStrings.entryCount(entryCount, maximum: maximumEntries)
	}

	@IBAction private func onUpdate(_: Any?) {
		clear()

		banListDelegate?.channelBanListSheetOnUpdate(self)
	}

	@IBAction private func onRemoveEntry(_: Any?) {
		let selectedEntries = entryTable.selectedRowIndexes.compactMap { row in
			tableEntries.indices.contains(row) ? tableEntries[row].entryMask : nil
		}

		listOfChanges = client.compileListOfModeChanges(
			forModeSymbol: modeSymbol,
			modeIsSet: false,
			modeParameters: selectedEntries
		)

		super.cancel(nil)
	}

	private var banListDelegate: (any ChannelBanListSheetDelegate)? {
		delegate as? any ChannelBanListSheetDelegate
	}

	@objc(channel:supportsEntryType:)
	public static func channel(
		_ channel: IRCChannel,
		supportsEntryType entryType: ChannelBanListEntryType
	) -> Bool {
		guard let client = channel.associatedClient else {
			return false
		}

		return client.supportInfo.isListSupported(entryType.supportListType)
	}

	@objc public var modeSymbol: String {
		client.supportInfo.modeSymbol(forList: entryType.supportListType) ?? ""
	}

	@objc public func windowWillClose(_: Notification) {
		banListDelegate?.channelBanListSheetWillClose(self)
	}
}

// MARK: - Table

extension ChannelBanListSheet: NSTableViewDelegate {
	/// Re-sorts and re-applies. The array controller used to do this through a
	/// `sortDescriptors` binding.
	public func tableView(_: NSTableView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
		applyEntries()
	}
}
