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
import Observation
import SwiftUI

@MainActor
public protocol ChannelBanListSheetDelegate: AnyObject {
	func channelBanListSheetOnUpdate(_ sender: ChannelBanListSheet)
	func channelBanListSheetWillClose(_ sender: ChannelBanListSheet)
}

public enum ChannelBanListEntryType: UInt {
	case ban = 0
	case banException
	case inviteException
	case quiet

	var supportListType: IRCISupportInfoListType {
		switch self {
		case .ban: .ban
		case .banException: .banException
		case .inviteException: .inviteException
		case .quiet: .quiet
		}
	}
}

public struct ChannelBanListSheetEntry: Identifiable, Hashable, Sendable {
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

struct ChannelBanListComparator: SortComparator {
	enum Field: Hashable, Sendable {
		case mask
		case author
		case creationDate
	}

	let field: Field
	var order: SortOrder

	func compare(_ lhs: ChannelBanListSheetEntry, _ rhs: ChannelBanListSheetEntry) -> ComparisonResult {
		let result = switch field {
		case .mask:
			lhs.entryMask.localizedCaseInsensitiveCompare(rhs.entryMask)
		case .author:
			lhs.entryAuthor.localizedCaseInsensitiveCompare(rhs.entryAuthor)
		case .creationDate:
			(lhs.entryCreationDate ?? .distantPast).compare(rhs.entryCreationDate ?? .distantPast)
		}

		guard order == .reverse else { return result }
		return switch result {
		case .orderedAscending: .orderedDescending
		case .orderedDescending: .orderedAscending
		case .orderedSame: .orderedSame
		}
	}
}

@Observable
final class ChannelBanListModel {
	var entries: [ChannelBanListSheetEntry] = []
	var selection: Set<ChannelBanListSheetEntry.ID> = []
	var sortOrder: [ChannelBanListComparator] = [
		ChannelBanListComparator(field: .creationDate, order: .reverse),
	]
	var maximumEntries = 0
	var isRefreshing = true

	var selectedMasks: [String] {
		entries.filter { selection.contains($0.id) }.map(\.entryMask)
	}

	var entryCountDescription: String {
		ChannelAccessListStrings.entryCount(entries.count, maximum: maximumEntries)
	}

	func add(_ entry: ChannelBanListSheetEntry) {
		entries.append(entry)
		sort(using: sortOrder)
	}

	func clear() {
		entries = []
		selection = []
	}

	func sort(using order: [ChannelBanListComparator]) {
		entries.sort(using: order)
	}
}

@MainActor
public final class ChannelBanListSheet: MainWindowSheetSession, ChannelScoped {
	public private(set) var client: IRCClient!
	public private(set) var channel: IRCChannel!
	public private(set) var clientId: String?
	public private(set) var channelId: String?
	public private(set) var entryType: ChannelBanListEntryType = .ban
	public private(set) var listOfChanges: [String]?
	public var contentAlreadyReceived = false {
		didSet { model.isRefreshing = contentAlreadyReceived == false }
	}

	let model = ChannelBanListModel()

	public init?(entryType: ChannelBanListEntryType, inChannel channel: IRCChannel) {
		guard Self.channel(channel, supportsEntryType: entryType),
		      let client = channel.associatedClient
		else { return nil }

		self.entryType = entryType
		self.client = client
		clientId = client.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier
		super.init(window: nil)

		model.maximumEntries = ChannelModeSymbol(modeSymbol)
			.map { Int(client.supportInfo.maximumListEntries(forModeSymbol: $0)) } ?? 0
		installSheet()
	}

	private func installSheet() {
		let heading = ChannelAccessListStrings.heading(for: entryType, channelName: channel.name)
		let rootView = ChannelBanListView(
			model: model,
			heading: heading,
			update: { [weak self] in self?.updateList() },
			removeSelected: { [weak self] in self?.removeSelectedEntries() },
			close: { [weak self] in self?.cancel(nil) }
		)
		setContent(rootView)
	}

	public func start() {
		startSheet()
	}

	public func clear() {
		model.clear()
	}

	public func addEntry(
		_ entryMask: String,
		setBy entryAuthor: String?,
		creationDate entryCreationDate: Date?
	) {
		var entry = ChannelBanListSheetEntry()
		entry.entryMask = entryMask
		entry.entryMaskDescription = client.supportInfo.descriptionForExtendedBanMask(entryMask)
		entry.entryAuthor = entryAuthor ?? ApplicationStrings.unknownValue
		entry.entryCreationDate = entryCreationDate
		model.add(entry)
	}

	public var entryCount: Int {
		model.entries.count
	}

	public var entryCountDescription: String {
		model.entryCountDescription
	}

	private func updateList() {
		model.clear()
		model.isRefreshing = true
		banListDelegate?.channelBanListSheetOnUpdate(self)
	}

	private func removeSelectedEntries() {
		guard model.selectedMasks.isEmpty == false else { return }
		listOfChanges = client.compileListOfModeChanges(
			forModeSymbol: modeSymbol,
			modeIsSet: false,
			modeParameters: model.selectedMasks
		)
		super.cancel(nil)
	}

	private var banListDelegate: (any ChannelBanListSheetDelegate)? {
		delegate as? any ChannelBanListSheetDelegate
	}

	public static func channel(
		_ channel: IRCChannel,
		supportsEntryType entryType: ChannelBanListEntryType
	) -> Bool {
		guard let client = channel.associatedClient else {
			return false
		}

		return client.supportInfo.isListSupported(entryType.supportListType)
	}

	public var modeSymbol: String {
		client.supportInfo.modeSymbol(forList: entryType.supportListType) ?? ""
	}

	override public func sheetDidEnd(withReturnCode _: Int) {
		banListDelegate?.channelBanListSheetWillClose(self)
	}
}
