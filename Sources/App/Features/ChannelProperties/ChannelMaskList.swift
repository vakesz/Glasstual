// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Observation
import SwiftUI

extension ChannelMaskKind {
	/// What the window is titled and the table is headed with: the list this is
	/// and the channel it belongs to. It lives with the window rather than with
	/// the kind so the heading's catalogue stays inside the feature that owns it.
	func heading(channelName: String) -> String {
		switch self {
		case .ban:
			String(localized: .ChannelProperties.headingForTheBanBans(channelName))
		case .banException:
			String(localized: .ChannelProperties.banExceptions(channelName))
		case .inviteException:
			String(localized: .ChannelProperties.inviteExceptions(channelName))
		case .quiet:
			String(localized: .ChannelProperties.headingForTheQuietQuiets(channelName))
		}
	}
}

extension ChannelMaskKind {
	/// What an empty table says, by the list it is: "No Bans" rather than a
	/// title that is the same whichever list came back empty.
	var emptyTitle: LocalizedStringResource {
		switch self {
		case .ban: .ChannelProperties.emptyTitleBans
		case .banException: .ChannelProperties.emptyTitleBanExceptions
		case .inviteException: .ChannelProperties.emptyTitleInviteExceptions
		case .quiet: .ChannelProperties.emptyTitleQuiets
		}
	}
}

/** Why a change to the list was not made, shown beside the field it came from.

 The server answers a refused `MODE` with an error numeric, and the window keeps
 the reason rather than letting it scroll past in a transcript the user is not
 looking at. */
enum ChannelMaskListIssue: Equatable, Sendable {
	case invalid(MaskNormalizer.Rejection)
	case duplicate
	/// `ERR_CHANOPRIVSNEEDED`.
	case notOperator
	/// `ERR_BANLISTFULL`.
	case listFull
	/// Any other refusal, with the text the server gave.
	case rejected(String)

	var message: String {
		switch self {
		case .invalid(.empty):
			String(localized: .ChannelProperties.issueEmpty)
		case .invalid(.containsWhitespace):
			String(localized: .ChannelProperties.issueWhitespace)
		case .invalid(.startsWithColon):
			String(localized: .ChannelProperties.issueColon)
		case .invalid(.tooLong):
			String(localized: .ChannelProperties.issueTooLong)
		case .duplicate:
			String(localized: .ChannelProperties.issueDuplicate)
		case .notOperator:
			String(localized: .ChannelProperties.issueNotOperator)
		case .listFull:
			String(localized: .ChannelProperties.issueListFull)
		case let .rejected(text):
			String(localized: .ChannelProperties.issueRejected(text))
		}
	}
}

struct ChannelMaskListEntry: Identifiable, Hashable, Sendable {
	let id = UUID()
	var entryMask = ""
	var entryMaskDescription: String?
	var entryAuthor = ""
	var entryCreationDate: Date?

	var entryCreationDateString: String {
		guard let entryCreationDate else {
			return ApplicationStrings.unknownValue
		}

		return entryCreationDate.formatted(date: .abbreviated, time: .shortened)
	}
}

struct ChannelMaskListComparator: SortComparator {
	enum Field: Hashable, Sendable {
		case mask
		case author
		case creationDate
	}

	let field: Field
	var order: SortOrder

	func compare(_ lhs: ChannelMaskListEntry, _ rhs: ChannelMaskListEntry) -> ComparisonResult {
		let result = switch field {
		case .mask:
			lhs.entryMask.localizedCaseInsensitiveCompare(rhs.entryMask)
		case .author:
			lhs.entryAuthor.localizedCaseInsensitiveCompare(rhs.entryAuthor)
		case .creationDate:
			(lhs.entryCreationDate ?? .distantPast).compare(rhs.entryCreationDate ?? .distantPast)
		}

		return result.ordered(by: order)
	}
}

@Observable
final class ChannelMaskListModel {
	var entries: [ChannelMaskListEntry] = []
	var selection: Set<ChannelMaskListEntry.ID> = []
	var sortOrder: [ChannelMaskListComparator] = [
		ChannelMaskListComparator(field: .creationDate, order: .reverse),
	]
	var maximumEntries = 0
	var isRefreshing = true
	/// What is typed in the field above the table.
	var draft = ""
	/// The entry the field is replacing, or `nil` while it adds a new one.
	var editingMask: String?
	/// Why the last change could not be made, until the next one is tried.
	var issue: ChannelMaskListIssue?
	/** How many entries the list keeps.

	 A channel's ban list arrives one line at a time and nothing bounded it, so
	 a list nobody has pruned in years was held whole. What is past the cap is
	 counted. */
	static let maximumRetainedEntries = 20000
	private(set) var discardedEntryCount = 0

	var selectedMasks: [String] {
		entries.filter { selection.contains($0.id) }.map(\.entryMask)
	}

	var entryCountDescription: String {
		Self.entryCountDescription(
			entries.count,
			maximum: maximumEntries,
			isTruncated: discardedEntryCount > 0
		)
	}

	/// - Parameter isTruncated: Whether the window dropped entries the server
	///   sent. Neither the bare count nor the `MAXLIST` comparison may be used
	///   then: both read as the list being all of it.
	static func entryCountDescription(_ count: Int, maximum: Int, isTruncated: Bool) -> String {
		if isTruncated {
			return String(localized: .ChannelProperties.entryCountTruncated(count))
		}

		guard maximum > 0 else {
			return String(localized: .ChannelProperties.entryCount(count))
		}

		return String(localized: .ChannelProperties.ofEntries(count, maximum))
	}

	/// What to tell the user when the list is not all of it, or `nil` when it
	/// is. The count above the table cannot say this on its own: a list cut at
	/// the cap reads as a complete one that happens to be exactly that long.
	var truncationNotice: LocalizedStringResource? {
		/* Why the count above the list is not the whole list. Saying how many
		 are shown as well would repeat the count itself. */
		discardedEntryCount > 0 ? .ChannelProperties.listTruncatedNotice : nil
	}

	func add(_ entry: ChannelMaskListEntry) {
		guard entries.count < Self.maximumRetainedEntries else {
			discardedEntryCount += 1
			return
		}

		entries.insert(entry, at: insertionIndex(for: entry))
	}

	/** Where `entry` belongs in the list as it is sorted now: after every entry
	 that does not sort after it, so entries that compare equal keep the order
	 they arrived in.

	 A binary search, because the list arrives one line at a time: re-sorting
	 the whole list for each line was quadratic, and at the cap that was twenty
	 thousand sorts on the main actor for one reply. */
	private func insertionIndex(for entry: ChannelMaskListEntry) -> Int {
		var lower = entries.startIndex
		var upper = entries.endIndex

		while lower < upper {
			let middle = lower + (upper - lower) / 2
			if Self.compare(entries[middle], entry, using: sortOrder) == .orderedDescending {
				upper = middle
			} else {
				lower = middle + 1
			}
		}

		return lower
	}

	/// The first comparator that tells the two apart decides, as `sort(using:)`
	/// does with the same array.
	private static func compare(
		_ lhs: ChannelMaskListEntry,
		_ rhs: ChannelMaskListEntry,
		using comparators: [ChannelMaskListComparator]
	) -> ComparisonResult {
		for comparator in comparators {
			let result = comparator.compare(lhs, rhs)
			if result != .orderedSame {
				return result
			}
		}

		return .orderedSame
	}

	func clear() {
		entries = []
		selection = []
		discardedEntryCount = 0
	}

	func sort(using order: [ChannelMaskListComparator]) {
		entries.sort(using: order)
	}
}

/** One channel access list -- bans, ban exceptions, invite exceptions or
 quiets -- as its own window.

 A modal sheet meant the list could not be read while the conversation it is
 about carried on, and every removal was a second trip through the menu. The
 window owns the table's model, asks the session for a refresh, and sends the
 mode changes the user makes as they are made.

 One at a time, which is why ``ChannelMaskListWindow`` keeps a single one of
 these: the reply that fills the table arrives through `ServerSessionPresenting` as a bare
 mask -- the numeric carries the channel and the mode letter, but the seam the
 transcript and the lists share does not -- so a second window open on another
 channel would have no way to tell which entries were its own. */
@MainActor
@Observable
final class ChannelMaskListSession: ChannelScoped {
	let session: ServerSession
	let channel: Conversation
	let maskKind: ChannelMaskKind
	let sessionId: String?
	let channelId: String?

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

	let model = ChannelMaskListModel()

	/// The refresh that follows a change, so a run of changes asks once.
	@ObservationIgnored private var pendingRefresh: Task<Void, Never>?
	/// How long a change waits for the server to apply it before the list is
	/// asked for again.
	static let refreshDelay: Duration = .milliseconds(600)

	init?(maskKind: ChannelMaskKind, in channel: Conversation) {
		guard Self.channel(channel, supportsMaskKind: maskKind),
		      let session = channel.associatedSession
		else { return nil }

		self.maskKind = maskKind
		self.session = session
		sessionId = session.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier

		/* The limit is whatever the server advertised in ISUPPORT, so it is
		 saturated rather than trusted to fit. */
		model.maximumEntries = modeSymbol
			.map { Int(clamping: session.supportInfo.maximumListEntries(forModeSymbol: $0)) } ?? 0
	}

	/// What the window is titled and the table is headed with.
	var heading: String {
		maskKind.heading(channelName: channel.name)
	}

	/** Whether a reply `session` sent for `channelName` under `modeSymbol` is
	 this list's.

	 The seam that carries these entries is shared with the transcript and is one
	 object for every connection, so a window open on another channel -- or on
	 another connection's `#channel` of the same name, or on the bans of a channel
	 whose invite list is also open -- would otherwise take entries that are not
	 its own. The channel name is compared under the server's casemapping,
	 because that is the only authority on whether two spellings name one
	 channel. */
	func matches(session: ServerSession, channelName: String, modeSymbol symbol: String) -> Bool {
		guard session === self.session, let modeSymbol, symbol == modeSymbol.description else {
			return false
		}

		return self.session.supportInfo.casefoldString(channelName)
			== self.session.supportInfo.casefoldString(channel.name)
	}

	/** Takes one entry from the server's reply.

	 The rows of the previous reply are held until this one starts arriving, so a
	 refresh never blanks the table before the new list lands -- which matters
	 more for a window than it did for a sheet, because the window is open across
	 every refresh the user asks for. */
	func receiveEntry(mask entryMask: String, setBy entryAuthor: String?, creationDate: Date?) {
		if previousReplyIsOnScreen {
			previousReplyIsOnScreen = false
			model.clear()
		}

		replyIsComplete = false

		var entry = ChannelMaskListEntry()
		entry.entryMask = entryMask
		entry.entryMaskDescription = session.supportInfo.descriptionForExtendedBanMask(entryMask)
		entry.entryAuthor = entryAuthor ?? ApplicationStrings.unknownValue
		entry.entryCreationDate = creationDate
		model.add(entry)
	}

	/// The server has sent the end of the list, so the spinner stops and the next
	/// entry to arrive belongs to a new reply.
	func finishReceiving() {
		if previousReplyIsOnScreen, replyIsComplete == false {
			model.clear()
		}
		replyIsComplete = true
		previousReplyIsOnScreen = true
	}

	/// Asks the server for the list again. The rows already up stay up until the
	/// new reply's first entry arrives, so the table is never a mix of two
	/// replies and never briefly empty either.
	func updateList() {
		guard let modeSymbol else { return }
		previousReplyIsOnScreen = true
		replyIsComplete = false
		/* `MODE #channel +b` with no mask is the request for the list. */
		session.sendModes([ModeChangeGroup(symbols: "+\(modeSymbol)")], inChannelNamed: channel.name)
	}

	/// Whether the user may change this list: an operator or half-operator of a
	/// channel they are in, on a server that still advertises the list. Read
	/// afresh each time, because privileges change while the window is open.
	/// The server stays the final authority and its refusal is shown inline.
	var canEdit: Bool {
		modeSymbol != nil
			&& ChannelActionPermissions(channel: channel, session: session).canChangeModes
	}

	/** Removing entries does not close the list.

	 The changes used to be held until the sheet closed, and the button closed
	 it -- so removing two entries meant opening the list twice. They are sent
	 as they are made, and the window stays open for the next one. The rows stay
	 until the refresh that follows shows what the server actually did. */
	func removeSelectedEntries() {
		let masks = model.selectedMasks
		guard canEdit, masks.isEmpty == false, let modeSymbol else { return }

		model.issue = nil
		session.sendModes(
			session.compileListOfModeChanges(
				forModeSymbol: modeSymbol.description,
				modeIsSet: false,
				modeParameters: masks
			),
			inChannelNamed: channel.name
		)
		scheduleRefresh()
	}

	/// Loads the selected entry into the field, so submitting replaces it.
	func beginEditingSelectedEntry() {
		guard canEdit, model.selection.count == 1, let mask = model.selectedMasks.first else { return }
		model.issue = nil
		model.editingMask = mask
		model.draft = mask
	}

	func cancelEditing() {
		model.editingMask = nil
		model.draft = ""
		model.issue = nil
	}

	/// Adds the draft, or replaces the entry being edited with it.
	func submitDraft() {
		guard canEdit, let modeSymbol else { return }

		let mask: String
		switch MaskNormalizer.normalize(model.draft) {
		case let .success(normalized):
			mask = normalized
		case let .failure(rejection):
			model.issue = .invalid(rejection)
			return
		}

		let symbol = modeSymbol.description
		if let editingMask = model.editingMask {
			guard mask.caseInsensitiveCompare(editingMask) != .orderedSame else {
				cancelEditing()
				return
			}
			guard containsEntry(mask) == false else {
				model.issue = .duplicate
				return
			}

			/* One group, so a server that takes two modes in a command applies the
			 swap together; one that takes fewer still gets the removal first. */
			session.sendModes(
				[ModeChangeGroup(symbols: "-\(symbol)+\(symbol)", parameters: [editingMask, mask])],
				inChannelNamed: channel.name
			)
		} else {
			guard containsEntry(mask) == false else {
				model.issue = .duplicate
				return
			}

			session.sendModes(
				session.compileListOfModeChanges(forModeSymbol: symbol, modeIsSet: true, modeParameters: [mask]),
				inChannelNamed: channel.name
			)
		}

		model.editingMask = nil
		model.draft = ""
		model.issue = nil
		scheduleRefresh()
	}

	private func containsEntry(_ mask: String) -> Bool {
		model.entries.contains { $0.entryMask.caseInsensitiveCompare(mask) == .orderedSame }
	}

	/** Takes the server's refusal of a change this list made.

	 Only the numerics a `MODE` on a list can draw are kept: a refusal for
	 another channel is not this window's, and the transcript prints it as it
	 always did. Called with the reply's raw numeric because the protocol layer
	 has no case for these. Answers whether the window took the refusal. */
	func receiveRefusal(
		session: ServerSession,
		channelName: String,
		numeric: UInt,
		text: String
	) -> Bool {
		/* `ERR_CHANOPRIVSNEEDED` also answers a kick or a topic change. Only a
		 refusal that arrives while a change of this list is waiting for its
		 refresh is the list's; any other still prints as an error. */
		guard pendingRefresh != nil, session === self.session,
		      session.supportInfo.casefoldString(channelName)
		      == session.supportInfo.casefoldString(channel.name)
		else { return false }

		let issue: ChannelMaskListIssue = switch numeric {
		case ChannelMaskListRefusal.chanOpPrivsNeeded: .notOperator
		case ChannelMaskListRefusal.banListFull: .listFull
		default: .rejected(text)
		}
		model.issue = issue
		/* The change did not happen, so what the table shows is still right, but
		 a refresh is cheap and drops any row another operator already changed. */
		scheduleRefresh()

		return true
	}

	/// Asks for the list again once the server has had time to apply a change.
	/// A newer change replaces the wait rather than adding a second request.
	private func scheduleRefresh() {
		pendingRefresh?.cancel()
		pendingRefresh = Task { [weak self] in
			try? await Task.sleep(for: Self.refreshDelay)
			guard Task.isCancelled == false else { return }
			self?.pendingRefresh = nil
			self?.updateList()
		}
	}

	/// Stops a refresh that has not fired, for a window that is going away.
	func cancelPendingRefresh() {
		pendingRefresh?.cancel()
		pendingRefresh = nil
	}

	static func channel(
		_ channel: Conversation,
		supportsMaskKind maskKind: ChannelMaskKind
	) -> Bool {
		guard let session = channel.associatedSession else {
			return false
		}

		return session.supportInfo.isListSupported(maskKind.supportListKind)
	}

	/** The mode letter this list is kept under.

	 `nil` once the server stops advertising the list: a `-` token withdraws one
	 mid-session and a reconnect resets ISUPPORT wholesale, either of which can
	 happen while the window is open. There is no mode to name then, so nothing
	 asks the session to change one. */
	var modeSymbol: ChannelModeSymbol? {
		session.supportInfo.modeSymbol(forList: maskKind.supportListKind)
			.flatMap(ChannelModeSymbol.init)
	}
}

/** The access-list window, and the list it is showing.

 One window, so opening a second channel's list replaces what it shows rather
 than adding a window whose replies it could not tell apart. That is why this is
 observable: the scene root reads the session through it, so a replacement
 redraws the window that is already up. */
@MainActor
@Observable
final class ChannelMaskListWindow {
	private(set) var current: ChannelMaskListSession?

	@ObservationIgnored private let scenes: ApplicationScenes

	init(scenes: ApplicationScenes = AppServices.scenes) {
		self.scenes = scenes
	}

	/** Opens one channel's access list, replacing whatever the window was
	 showing.

	 A window rather than a sheet, so the channel the list is about can be read
	 and typed into while its entries are being looked over. The mode query that
	 fills it is sent by the caller, so the session is in place before the first
	 reply can arrive. */
	func open(maskKind: ChannelMaskKind, in channel: Conversation) {
		guard let session = ChannelMaskListSession(maskKind: maskKind, in: channel) else { return }
		current = session
		scenes.open(ApplicationSceneID.channelMaskList)
	}

	func didClose() {
		current?.cancelPendingRefresh()
		current = nil
	}

	/// Offers a refused change to the open list. `true` when it was this list's.
	func receiveRefusal(session: ServerSession, channelName: String, numeric: UInt, text: String) -> Bool {
		current?.receiveRefusal(session: session, channelName: channelName, numeric: numeric, text: text) ?? false
	}

	/// Closes the list when the channel or connection it is about goes away,
	/// which is what the sheet it replaced got from the main window.
	func close(matching isStale: (ChannelMaskListSession) -> Bool) {
		guard let session = current, isStale(session) else { return }
		session.cancelPendingRefresh()
		current = nil
		scenes.dismiss(ApplicationSceneID.channelMaskList)
	}
}
