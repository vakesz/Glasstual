// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/*  The values one render is a function of.

 A render job runs off the main actor, so everything it may read is copied into
 a context first: the conversation's members under the server's casemapping, and the
 setting facts the body renderer branches on. The line it draws is copied the
 same way, into a ``ChatLineSnapshot``. */

nonisolated struct RenderedMember: Sendable, Hashable {
	var nickname: String
	var mark: String

	init(nickname: String, mark: String = "") {
		self.nickname = nickname
		self.mark = mark
	}

	init(_ member: Member) {
		self.init(nickname: member.user.nickname, mark: member.mark)
	}
}

/** The conversation's members as a render reads them: by name, under the casemapping
 the server advertised.

 Built once per change to the member list and shared by every line rendered
 against it. A render asks it about each word of a message and about each
 line's sender, so both are lookups rather than walks of the whole list. */
nonisolated struct RenderedMemberDirectory: Equatable, Sendable, ExpressibleByArrayLiteral {
	/// The members in the order the member list holds them.
	let members: [RenderedMember]
	let caseMapping: ISupportCaseMapping
	/// Each member under their folded name. The first spelling wins where two
	/// fold alike, which a server that enforces its casemapping never sends.
	private let membersByFoldedNickname: [String: RenderedMember]
	/// The distinct lengths of the members' names, in UTF-16 units, shortest
	/// first: the only lengths a mention can have.
	let nicknameLengths: [Int]

	init(_ members: [RenderedMember], caseMapping: ISupportCaseMapping = .rfc1459) {
		self.members = members
		self.caseMapping = caseMapping
		var byName: [String: RenderedMember] = [:]
		var lengths = Set<Int>()
		for member in members where member.nickname.isEmpty == false {
			let folded = IRCCaseFolding.fold(member.nickname, using: caseMapping)
			if byName[folded] == nil {
				byName[folded] = member
			}
			lengths.insert((member.nickname as NSString).length)
		}
		membersByFoldedNickname = byName
		nicknameLengths = lengths.sorted()
	}

	init(arrayLiteral members: RenderedMember...) {
		self.init(members)
	}

	var isEmpty: Bool {
		members.isEmpty
	}

	/// The member `nickname` names under the casemapping, however it is spelled.
	func member(named nickname: String) -> RenderedMember? {
		membersByFoldedNickname[IRCCaseFolding.fold(nickname, using: caseMapping)]
	}

	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.members == rhs.members && lhs.caseMapping == rhs.caseMapping
	}
}

nonisolated struct TranscriptRenderContext: Sendable {
	var inlineMediaEnabled = false
	var isChannel = false
	/// Whether a day boundary is drawn between lines. It is read from the
	/// settings on the main actor and carried here, so rendering stays a
	/// function of the values it was handed.
	var showsDateChanges = false
	/// The setting facts the body renderer branches on, taken on the main
	/// actor for the same reason `showsDateChanges` is.
	var textPolicy = TranscriptTextRules()
	/// The conversation's members, for the mentions in a message and the mark
	/// beside its sender. Empty where the lines rendered need neither.
	var members: RenderedMemberDirectory = []
	/// The server's casemapping, which decides what spells the same name.
	var caseMapping = ISupportCaseMapping.rfc1459
	var sessionReactions: [String: ReactionsByEmoji] = [:]

	func reactions(for line: ChatLineSnapshot) -> ReactionsByEmoji {
		let archived = line.reactions ?? [:]
		guard let identifier = line.messageIdentifier,
		      let session = sessionReactions[identifier],
		      session.isEmpty == false
		else {
			return archived
		}
		var merged = archived
		for (emoji, nicknames) in session {
			var values = merged[emoji] ?? []
			for nickname in nicknames where values.contains(nickname) == false {
				values.append(nickname)
			}
			merged[emoji] = values
		}
		return merged
	}
}

nonisolated struct ChatLineSnapshot: Sendable {
	var uniqueIdentifier = ""
	var messageBody = ""
	var command = ""
	var receivedAt = Date()
	var lineType = ChatLineKind.undefined
	var memberType = ChatLineMemberKind.normal
	var nickname: String?
	var messageIdentifier: String?
	var replyToMessageIdentifier: String?
	var deliveryState = ChatLineDeliveryState.none
	var reactions: [String: [String]]?
	var highlightKeywords: [String]?
	var excludeKeywords: [String]?
	var isEncrypted = false
	var isFirstForDay = false
	var fromCurrentSession = true
	var modeSymbol = ""
	var historyCursor: ScrollbackRowCursor?

	init() {}

	/// `modeSymbol` is the sender's mark where the caller already knows it; a
	/// line rendered off the main actor finds it in the context's members.
	init(
		_ chatLine: ChatLine,
		in context: TranscriptRenderContext,
		historyCursor: ScrollbackRowCursor? = nil,
		modeSymbol knownModeSymbol: String? = nil
	) {
		self.historyCursor = historyCursor
		uniqueIdentifier = historyCursor?.rowURI ?? chatLine.uniqueIdentifier
		messageBody = chatLine.messageBody
		command = chatLine.command
		receivedAt = chatLine.receivedAt
		lineType = chatLine.lineType
		memberType = chatLine.memberType
		nickname = chatLine.nickname
		messageIdentifier = chatLine.messageIdentifier
		replyToMessageIdentifier = chatLine.replyToMessageIdentifier
		deliveryState = chatLine.deliveryState
		reactions = chatLine.reactions
		highlightKeywords = chatLine.highlightKeywords
		excludeKeywords = chatLine.excludeKeywords
		isEncrypted = chatLine.isEncrypted
		isFirstForDay = chatLine.isFirstForDay
		fromCurrentSession = chatLine.fromCurrentSession

		modeSymbol = if let knownModeSymbol {
			knownModeSymbol
		} else if context.isChannel, let sender = chatLine.nickname {
			context.members.member(named: sender)?.mark ?? ""
		} else {
			""
		}
	}
}
