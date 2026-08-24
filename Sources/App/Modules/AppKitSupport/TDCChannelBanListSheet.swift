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

@objc(TDCChannelBanListSheetEntry)
public final class ChannelBanListSheetEntry: NSObject {
	@objc public var entryMask = ""
	@objc public var entryMaskDescription: String?
	@objc public var entryAuthor = ""
	@objc public var entryCreationDate: Date?

	@objc public var entryCreationDateString: String {
		guard let entryCreationDate else {
			return LocalizedKey("BasicLanguage[vbl-xi]")
		}

		return formatDateLongStyle(entryCreationDate, true) ?? LocalizedKey("BasicLanguage[vbl-xi]")
	}
}

@objc(TDCChannelBanListSheet)
@MainActor
public final class ChannelBanListSheet: SheetBase {
	@objc public private(set) var client: IRCClient!
	@objc public private(set) var channel: IRCChannel!
	@objc public private(set) var clientId = ""
	@objc public private(set) var channelId = ""
	@objc public private(set) var entryType: TDCChannelBanListSheetEntryType = .ban
	@objc public private(set) var listOfChanges: [String]?
	@objc public var contentAlreadyReceived = false

	@IBOutlet private var headerTitleTextField: NSTextField!
	@IBOutlet private var entryTable: BasicTableView!
	@IBOutlet private var entryTableController: NSArrayController!

	private var tableEntries: [Any] {
		entryTableController.arrangedObjects as? [Any] ?? []
	}

	@objc(initWithEntryType:inChannel:)
	public init?(entryType: TDCChannelBanListSheetEntryType, inChannel channel: IRCChannel) {
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

		let headerTitle: String? = switch entryType {
		case .ban:
			LocalizedKey("TDCChannelBanListSheet[rhc-ke]", channel.name)
		case .banException:
			LocalizedKey("TDCChannelBanListSheet[gbi-wn]", channel.name)
		case .inviteException:
			LocalizedKey("TDCChannelBanListSheet[ylc-6e]", channel.name)
		case .quiet:
			LocalizedKey("TDCChannelBanListSheet[g4r-t6]", channel.name)
		@unknown default:
			nil
		}

		if let headerTitle {
			headerTitleTextField.stringValue = headerTitle
		}
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
			author = LocalizedKey("BasicLanguage[vbl-xi]")
		}

		let newEntry = ChannelBanListSheetEntry()
		newEntry.entryMask = entryMask
		newEntry.entryMaskDescription = client.supportInfo.description(forExtendedBanMask: entryMask)
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

		if maximumEntries > 0 {
			return LocalizedKey(
				"TDCChannelBanListSheet[n0f-mx]",
				formattedNumber(entryCount),
				formattedNumber(maximumEntries)
			)
		}

		return LocalizedKey("TDCChannelBanListSheet[n0f-cn]", formattedNumber(entryCount))
	}

	@IBAction private func onUpdate(_: Any?) {
		clear()

		let selector = NSSelectorFromString("channelBanListSheetOnUpdate:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
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

	@objc(channel:supportsEntryType:)
	public class func channel(
		_ channel: IRCChannel,
		supportsEntryType entryType: TDCChannelBanListSheetEntryType
	) -> Bool {
		guard let listType = IRCISupportInfoListType(rawValue: entryType.rawValue) else {
			return false
		}

		return channel.associatedClient!.supportInfo.isListSupported(listType)
	}

	@objc public var modeSymbol: String {
		let listType = IRCISupportInfoListType(rawValue: entryType.rawValue)!
		return client.supportInfo.modeSymbol(for: listType) ?? ""
	}

	@objc public func windowWillClose(_: Notification) {
		let selector = NSSelectorFromString("channelBanListSheetWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
