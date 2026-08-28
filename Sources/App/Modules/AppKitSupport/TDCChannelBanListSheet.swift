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

@objc(TDCChannelBanListSheetEntry)
public final class ChannelBanListSheetEntry: NSObject {
	@objc public var entryMask = ""
	@objc public var entryMaskDescription: String?
	@objc public var entryAuthor = ""
	@objc public var entryCreationDate: Date?

	@objc public var entryCreationDateString: String {
		guard let entryCreationDate else {
			return ApplicationStrings.unknownValue
		}

		return formatDateLongStyle(entryCreationDate, true) ?? ApplicationStrings.unknownValue
	}
}

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
	@IBOutlet private var entryTableController: NSArrayController!

	private var tableEntries: [Any] {
		entryTableController.arrangedObjects as? [Any] ?? []
	}

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

		entryTable.sortDescriptors = [
			NSSortDescriptor(key: "entryCreationDate", ascending: false, selector: #selector(NSDate.compare(_:))),
		]

		headerTitleTextField.stringValue = ChannelAccessListStrings.heading(
			for: entryType,
			channelName: channel.name
		)
	}

	@objc public func start() {
		startSheet()
	}

	@objc public func clear() {
		willChangeValue(forKey: "entryCount")
		willChangeValue(forKey: "entryCountDescription")

		entryTableController.content = nil

		didChangeValue(forKey: "entryCountDescription")
		didChangeValue(forKey: "entryCount")
	}

	@objc(addEntry:setBy:creationDate:)
	public func addEntry(
		_ entryMask: String,
		setBy entryAuthor: String?,
		creationDate entryCreationDate: Date?
	) {
		var author = entryAuthor

		if author == nil {
			author = ApplicationStrings.unknownValue
		}

		let newEntry = ChannelBanListSheetEntry()
		newEntry.entryMask = entryMask
		newEntry.entryMaskDescription = client.supportInfo.descriptionForExtendedBanMask(entryMask)
		newEntry.entryAuthor = author!
		newEntry.entryCreationDate = entryCreationDate

		willChangeValue(forKey: "entryCount")
		willChangeValue(forKey: "entryCountDescription")

		entryTableController.addObject(newEntry)

		didChangeValue(forKey: "entryCountDescription")
		didChangeValue(forKey: "entryCount")
	}

	@objc public dynamic var entryCount: NSNumber {
		NSNumber(value: tableEntries.count)
	}

	@objc public dynamic var entryCountDescription: String {
		let entryCount = tableEntries.count
		let maximumEntries = Int(client.supportInfo.maximumListEntries(forModeSymbol: modeSymbol))

		return ChannelAccessListStrings.entryCount(entryCount, maximum: maximumEntries)
	}

	@IBAction private func onUpdate(_: Any?) {
		clear()

		banListDelegate?.channelBanListSheetOnUpdate(self)
	}

	@IBAction private func onRemoveEntry(_: Any?) {
		let selectedRows = entryTable.selectedRowIndexes
		var selectedEntries: [String] = []

		for index in selectedRows {
			guard let entryItem = tableEntries[index] as? ChannelBanListSheetEntry else {
				continue
			}

			selectedEntries.append(entryItem.entryMask)
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
