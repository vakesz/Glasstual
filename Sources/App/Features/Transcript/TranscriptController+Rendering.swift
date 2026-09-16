/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

/// Initial replay keeps raw archives distinct from the native rows it rendered.
nonisolated struct TranscriptHistoryRenderOutput: Sendable { // nonisolated: value
	let historicEntries: [LogLine]
	let results: [TranscriptRenderResult]
	let fetchSucceeded: Bool
	let failure: ScrollbackFetchFailure?
}

nonisolated struct RenderedMember: Sendable, Hashable { // nonisolated: value
	var nickname: String
	var mark: String

	init(nickname: String, mark: String = "") {
		self.nickname = nickname
		self.mark = mark
	}

	init(_ member: ChannelUser) {
		self.init(nickname: member.user.nickname, mark: member.mark)
	}
}

/** The channel's members as a render reads them: by name, under the casemapping
 the server advertised.

 Built once per change to the member list and shared by every line rendered
 against it. A render asks it about each word of a message and about each
 line's sender, so both are lookups rather than walks of the whole channel. */
nonisolated struct RenderedMemberDirectory: Equatable, Sendable, ExpressibleByArrayLiteral { // nonisolated: value
	/// The members in the order the channel lists them.
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
			let folded = ISupportTokenParser.casefold(member.nickname, caseMapping: caseMapping)
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
		membersByFoldedNickname[ISupportTokenParser.casefold(nickname, caseMapping: caseMapping)]
	}

	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.members == rhs.members && lhs.caseMapping == rhs.caseMapping
	}
}

nonisolated struct TranscriptRenderContext: Sendable { // nonisolated: value
	var inlineMediaEnabled = false
	var isChannel = false
	/// Whether a day boundary is drawn between lines. It is read from the
	/// preferences on the main actor and carried here, so rendering stays a
	/// function of the values it was handed.
	var showsDateChanges = false
	/// The preference facts the body renderer branches on, taken on the main
	/// actor for the same reason `showsDateChanges` is.
	var textPolicy = TranscriptTextPolicy()
	/// The channel's members, for the mentions in a message and the mark
	/// beside its sender. Empty where the lines rendered need neither.
	var members: RenderedMemberDirectory = []
	/// The server's casemapping, which decides what spells the same name.
	var caseMapping = ISupportCaseMapping.rfc1459
	var sessionReactions: [String: [String: [String]]] = [:]

	func reactions(for line: LogLineSnapshot) -> [String: [String]] {
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

nonisolated struct LogLineSnapshot: Sendable { // nonisolated: value
	var uniqueIdentifier = ""
	var messageBody = ""
	var command = ""
	var receivedAt = Date()
	var lineType = LogLineType.undefined
	var memberType = LogLineMemberType.normal
	var nickname: String?
	var messageIdentifier: String?
	var replyToMessageIdentifier: String?
	var deliveryState = LogLineDeliveryState.none
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
		_ logLine: LogLine,
		in context: TranscriptRenderContext,
		historyCursor: ScrollbackRowCursor? = nil,
		modeSymbol knownModeSymbol: String? = nil
	) {
		self.historyCursor = historyCursor
		uniqueIdentifier = historyCursor?.rowURI ?? logLine.uniqueIdentifier
		messageBody = logLine.messageBody
		command = logLine.command
		receivedAt = logLine.receivedAt
		lineType = logLine.lineType
		memberType = logLine.memberType
		nickname = logLine.nickname
		messageIdentifier = logLine.messageIdentifier
		replyToMessageIdentifier = logLine.replyToMessageIdentifier
		deliveryState = logLine.deliveryState
		reactions = logLine.reactions
		highlightKeywords = logLine.highlightKeywords
		excludeKeywords = logLine.excludeKeywords
		isEncrypted = logLine.isEncrypted
		isFirstForDay = logLine.isFirstForDay
		fromCurrentSession = logLine.fromCurrentSession

		modeSymbol = if let knownModeSymbol {
			knownModeSymbol
		} else if context.isChannel, let sender = logLine.nickname {
			context.members.member(named: sender)?.mark ?? ""
		} else {
			""
		}
	}
}

nonisolated struct TranscriptRenderRequest: Sendable { // nonisolated: value
	var line: LogLineSnapshot
	var context: TranscriptRenderContext
}

nonisolated struct TranscriptRenderResult: Sendable { // nonisolated: value
	var transcriptLine: TranscriptRow
	var fromCurrentSession: Bool
	var processesInlineMedia: Bool

	var lineNumber: String {
		transcriptLine.lineNumber
	}

	var isHighlight: Bool {
		transcriptLine.body.isHighlight
	}

	var links: [LinkParserResult] {
		transcriptLine.body.links
	}

	var mentionedNicknames: [String] {
		transcriptLine.body.mentionedNicknames
	}
}

extension TranscriptController {
	nonisolated static func renderJob( // nonisolated: pure
		_ lines: [LogLineSnapshot],
		context: TranscriptRenderContext
	) -> [TranscriptRenderResult] {
		lines.map { renderJob(TranscriptRenderRequest(line: $0, context: context)) }
	}

	nonisolated static func renderJob( // nonisolated: pure
		_ request: TranscriptRenderRequest
	) -> TranscriptRenderResult {
		let line = request.line
		let attributes = TranscriptRenderOptions(
			renderLinks: !LinkParser.bannedLineTypes.contains(LogLine.string(for: line.lineType) ?? ""),
			lineType: line.lineType,
			memberType: line.memberType,
			highlightKeywords: line.highlightKeywords ?? [],
			excludedKeywords: line.excludeKeywords ?? [],
			textPolicy: request.context.textPolicy,
			caseMapping: request.context.caseMapping
		)

		let body = TranscriptRenderer.renderNativeBody(
			line.messageBody,
			withAttributes: attributes,
			members: request.context.members.members
		)
		let markers = markers(for: request)
		let transcriptLine = TranscriptRow(
			lineNumber: line.uniqueIdentifier,
			receivedAt: line.receivedAt,
			nickname: line.nickname,
			memberType: line.memberType,
			lineType: line.lineType,
			command: line.command,
			messageIdentifier: line.messageIdentifier,
			replyToMessageIdentifier: line.replyToMessageIdentifier,
			deliveryState: line.deliveryState,
			deliveryFailureReason: nil,
			reactions: request.context.reactions(for: line),
			markers: markers,
			body: body,
			modeSymbol: line.modeSymbol,
			historyCursor: line.historyCursor
		)
		let inlineMedia = request.context.inlineMediaEnabled &&
			(line.lineType == .privateMessage || line.lineType == .action)
		return TranscriptRenderResult(
			transcriptLine: transcriptLine,
			fromCurrentSession: line.fromCurrentSession,
			processesInlineMedia: inlineMedia
		)
	}

	private nonisolated static func markers( // nonisolated: pure
		for request: TranscriptRenderRequest
	)
		-> [TranscriptMarker]
	{
		var result: [TranscriptMarker] = []
		if request.line.isFirstForDay, request.context.showsDateChanges {
			result.append(.date(DateFormatting.formatted(request.line.receivedAt, dateStyle: .long, timeStyle: .none, relative: false)))
		}
		return result
	}
}

/** The channel's members as the renderer reads them, rebuilt only when the
 names, marks, membership or casemapping change.

 Owned by a transcript controller. Away, account and conversation edits do not
 rebuild it; nor does printing, however many lines use it. */
@MainActor
final class TranscriptMemberDirectoryCache {
	private weak var memberList: ChannelMemberList?
	private var revision: UInt64?
	private var directory: RenderedMemberDirectory = []
	/// How many times the directory was built, which is what says a burst of
	/// prints or a conversation-weight edit reused it.
	private(set) var rebuildCount = 0

	func members(in channel: Channel?) -> RenderedMemberDirectory {
		guard let list = channel?.memberInfo else {
			memberList = nil
			revision = nil
			directory = []
			return []
		}
		let caseMapping = channel?.associatedClient?.supportInfo.caseMapping ?? .rfc1459
		if memberList !== list || revision != list.renderRevision || directory.caseMapping != caseMapping {
			memberList = list
			revision = list.renderRevision
			directory = RenderedMemberDirectory(list.memberList.map(RenderedMember.init), caseMapping: caseMapping)
			rebuildCount += 1
		}
		return directory
	}
}
