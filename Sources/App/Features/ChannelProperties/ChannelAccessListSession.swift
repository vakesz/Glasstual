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
	/** How many entries the list keeps.

	 A channel's ban list arrives one line at a time and nothing bounded it, so
	 a list nobody has pruned in years was held whole and re-sorted on every
	 line. What is past the cap is counted. */
	static let maximumRetainedEntries = 20000
	private(set) var discardedEntryCount = 0

	var selectedMasks: [String] {
		entries.filter { selection.contains($0.id) }.map(\.entryMask)
	}

	var entryCountDescription: String {
		ChannelAccessListStrings.entryCount(
			entries.count,
			maximum: maximumEntries,
			isTruncated: discardedEntryCount > 0
		)
	}

	/// What to tell the user when the list is not all of it, or `nil` when it
	/// is. The count above the table cannot say this on its own: a list cut at
	/// the cap reads as a complete one that happens to be exactly that long.
	var truncationNotice: String? {
		guard discardedEntryCount > 0 else { return nil }

		return ChannelAccessListStrings.truncationNotice(shownEntryCount: entries.count)
	}

	func add(_ entry: ChannelBanListSheetEntry) {
		guard entries.count < Self.maximumRetainedEntries else {
			discardedEntryCount += 1
			return
		}

		entries.append(entry)
		sort(using: sortOrder)
	}

	func clear() {
		entries = []
		selection = []
		discardedEntryCount = 0
	}

	/// Drops the rows the server has just been told to unset, so the list shows
	/// what it asked for without waiting for the server to say it again.
	func remove(masks: [String]) {
		let removed = Set(masks)
		entries.removeAll { removed.contains($0.entryMask) }
		selection = []
	}

	func sort(using order: [ChannelBanListComparator]) {
		entries.sort(using: order)
	}
}

/** The access list the window is showing, and nothing else.

 One at a time, because the reply that fills it arrives through `ClientOutput`
 as a bare mask: the numeric carries the channel and the mode letter, but the
 seam the transcript and the lists share does not, so a second window open on
 another channel would have no way to tell which entries were its own. Holding
 the session here rather than on `ApplicationScenes` is what lets the window
 follow a replacement -- the scene root observes this, so opening the list for
 another channel redraws the window that is already up. */
@MainActor
@Observable
final class ChannelAccessListWindowState {
	var session: ChannelAccessListSession?
}

/** One channel access list -- bans, ban exceptions, invite exceptions or
 quiets -- as its own window.

 A modal sheet meant the list could not be read while the conversation it is
 about carried on, and every removal was a second trip through the menu. The
 window owns the table's model, asks the client for a refresh, and sends the
 mode changes the user makes as they are made. */
@MainActor
@Observable
public final class ChannelAccessListSession: ChannelScoped {
	public let client: IRCClient
	public let channel: IRCChannel
	public let entryType: ChannelBanListEntryType
	public let clientId: String?
	public let channelId: String?

	/// Whether the server has sent the end of the reply the table is showing.
	private var replyIsComplete = false {
		didSet { model.isRefreshing = replyIsComplete == false }
	}

	/** Whether the rows on screen belong to a reply this session is done with.

	 Set when the server ends a reply and when a refresh is asked for, cleared
	 by the first entry of the next reply — which is the entry that replaces
	 them. Holding the rows this way is what keeps a window that is open across
	 a refresh from blanking before the new list lands. */
	private var previousReplyIsOnScreen = false

	let model = ChannelBanListModel()

	public init?(entryType: ChannelBanListEntryType, in channel: IRCChannel) {
		guard Self.channel(channel, supportsEntryType: entryType),
		      let client = channel.associatedClient
		else { return nil }

		self.entryType = entryType
		self.client = client
		clientId = client.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier

		/* The limit is whatever the server advertised in ISUPPORT, so it is
		 saturated rather than trusted to fit. */
		model.maximumEntries = modeSymbol
			.map { Int(clamping: client.supportInfo.maximumListEntries(forModeSymbol: $0)) } ?? 0
	}

	/// What the window is titled and the table is headed with: the list this is
	/// and the channel it belongs to.
	var heading: String {
		ChannelAccessListStrings.heading(for: entryType, channelName: channel.name)
	}

	/** Whether a reply `client` sent for `channelName` under `modeSymbol` is
	 this list's.

	 The seam that carries these entries is shared with the transcript and is one
	 object for every connection, so a window open on another channel -- or on
	 another connection's `#channel` of the same name, or on the bans of a channel
	 whose invite list is also open -- would otherwise take entries that are not
	 its own. The channel name is compared under the server's casemapping,
	 because that is the only authority on whether two spellings name one
	 channel. */
	public func matches(client: IRCClient, channelName: String, modeSymbol symbol: String) -> Bool {
		guard client === self.client, let modeSymbol, symbol == modeSymbol.description else {
			return false
		}

		return self.client.supportInfo.casefoldString(channelName)
			== self.client.supportInfo.casefoldString(channel.name)
	}

	/** Takes one entry from the server's reply.

	 The rows of the previous reply are held until this one starts arriving, so a
	 refresh never blanks the table before the new list lands -- which matters
	 more for a window than it did for a sheet, because the window is open across
	 every refresh the user asks for. */
	public func receiveEntry(mask entryMask: String, setBy entryAuthor: String?, creationDate: Date?) {
		if previousReplyIsOnScreen {
			previousReplyIsOnScreen = false
			model.clear()
		}

		replyIsComplete = false

		var entry = ChannelBanListSheetEntry()
		entry.entryMask = entryMask
		entry.entryMaskDescription = client.supportInfo.descriptionForExtendedBanMask(entryMask)
		entry.entryAuthor = entryAuthor ?? ApplicationStrings.unknownValue
		entry.entryCreationDate = creationDate
		model.add(entry)
	}

	/// The server has sent the end of the list, so the spinner stops and the next
	/// entry to arrive belongs to a new reply.
	public func finishReceiving() {
		replyIsComplete = true
		previousReplyIsOnScreen = true
	}

	/// Asks the server for the list again. The rows already up stay up until the
	/// new reply's first entry arrives, so the table is never a mix of two
	/// replies and never briefly empty either.
	func updateList() {
		previousReplyIsOnScreen = true
		replyIsComplete = false
		guard let modeSymbol else { return }
		/* `MODE #channel +b` with no mask is the request for the list. */
		client.sendModes([ModeChangeGroup(symbols: "+\(modeSymbol)")], in: channel)
	}

	/** Removing entries does not close the list.

	 The changes used to be held until the sheet closed, and the button closed
	 it -- so removing two entries meant opening the list twice. They are sent
	 as they are made, and the window stays open for the next one. */
	func removeSelectedEntries() {
		let masks = model.selectedMasks
		guard masks.isEmpty == false, let modeSymbol else { return }

		client.sendModes(
			client.compileListOfModeChanges(
				forModeSymbol: modeSymbol.description,
				modeIsSet: false,
				modeParameters: masks
			),
			in: channel
		)
		model.remove(masks: masks)
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

	/** The mode letter this list is kept under.

	 `nil` once the server stops advertising the list: a `-` token withdraws one
	 mid-session and a reconnect resets ISUPPORT wholesale, either of which can
	 happen while the window is open. There is no mode to name then, so nothing
	 asks the client to change one. */
	public var modeSymbol: ChannelModeSymbol? {
		client.supportInfo.modeSymbol(forList: entryType.supportListType)
			.flatMap(ChannelModeSymbol.init)
	}
}
