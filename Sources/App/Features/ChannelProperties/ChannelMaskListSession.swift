// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

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
