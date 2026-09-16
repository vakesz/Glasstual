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

import Foundation

nonisolated struct TranscriptTextTraits: OptionSet, Equatable, Sendable { // nonisolated: value
	let rawValue: UInt8

	static let bold = Self(rawValue: 1 << 0)
	static let italic = Self(rawValue: 1 << 1)
	static let monospace = Self(rawValue: 1 << 2)
	static let strikethrough = Self(rawValue: 1 << 3)
	static let underline = Self(rawValue: 1 << 4)
	static let highlighted = Self(rawValue: 1 << 5)
}

nonisolated enum TranscriptRunColor: Equatable, Sendable { // nonisolated: value
	case palette(Int)
	case rgb(TranscriptThemeColor)
}

nonisolated enum TranscriptRunAction: Equatable, Sendable { // nonisolated: value
	case link(URL)
	case channel(String)
	case nickname(String)
}

nonisolated struct TranscriptTextRun: Equatable, Sendable { // nonisolated: value
	var text: String
	var traits: TranscriptTextTraits = []
	var foreground: TranscriptRunColor?
	var background: TranscriptRunColor?
	var action: TranscriptRunAction?
}

nonisolated struct TranscriptBody: Equatable, Sendable { // nonisolated: value
	var plainText = ""
	var runs: [TranscriptTextRun] = []
	var links: [LinkParserResult] = []
	var mentionedNicknames: [String] = []
	var isHighlight = false
}

nonisolated enum TranscriptMarker: Equatable, Sendable { // nonisolated: value
	case date(String)
	case currentSession(String)
	case unread(String)
}

/// One complete native transcript row. It is independent of AppKit so render
/// jobs can build it concurrently and the view can restyle it without parsing
/// source text or markup again.
nonisolated struct TranscriptRow: Equatable, Sendable { // nonisolated: value
	var lineNumber: String
	var receivedAt: Date
	var nickname: String?
	var memberType: LogLineMemberType
	var lineType: LogLineType
	var command: String
	var messageIdentifier: String?
	var replyToMessageIdentifier: String?
	var deliveryState: LogLineDeliveryState
	var deliveryFailureReason: String?
	var reactions: [String: [String]]
	var markers: [TranscriptMarker]
	var body: TranscriptBody
	var modeSymbol = ""
	var historyCursor: ScrollbackRowCursor?

	/** Whether `identifier` names this row.

	 A row restored from storage answers to two identifiers: the line number it
	 was printed with, and the identifier of the history row it came back from.
	 Everything that looks a row up by number — jumping, marking, delivery and
	 duplicate checks — has to accept both, so it asks here. */
	func matches(identifier: String) -> Bool {
		lineNumber == identifier || historyCursor?.lineIdentifier == identifier
	}

	/// Both of them, for the set the transcript answers duplicate questions from.
	var identifiers: [String] {
		[lineNumber, historyCursor?.lineIdentifier].compactMap(\.self)
	}

	mutating func mergeReactions(_ delta: [String: [String]]) {
		for (emoji, nicknames) in delta {
			for nickname in nicknames where !reactions[emoji, default: []].contains(nickname) {
				reactions[emoji, default: []].append(nickname)
			}
		}
	}

	/// The timestamp and sender the row is drawn with. Main-actor because the
	/// nickname format is applied by the same presentation code a printed line
	/// uses, which reads the theme on this actor.
	@MainActor
	func header(using theme: TranscriptTheme) -> (timestamp: String, nickname: String) {
		let timestamp = DateFormatting.timestamp(receivedAt, format: theme.timestampFormat) ?? ""
		guard let wireNickname = nickname else { return (timestamp, "") }
		/* A name is wire text like a message body, and is held to one line the
		 same way. */
		let nickname = TranscriptTextSanitizer.singleLine(wireNickname)
		let formattedNickname: String = switch lineType {
		case .action: String(format: LogLineFormat.actionNickname, nickname)
		case .notice: String(format: LogLineFormat.noticeNickname, nickname)
		default:
			formattedNickname(
				nickname, modeSymbol: modeSymbol,
				format: theme.nicknameFormat.isEmpty ? TranscriptTheme.lines.nicknameFormat : theme.nicknameFormat
			)
		}
		return (timestamp, formattedNickname.trimmingCharacters(in: .whitespacesAndNewlines))
	}

	var isMessage: Bool {
		lineType == .privateMessage || lineType == .action || lineType == .notice
	}

	var lineTypeString: String {
		LogLine.string(for: lineType) ?? ""
	}
}

nonisolated struct TranscriptInlineImage: Equatable, Sendable { // nonisolated: value
	var lineNumber: String
	var linkIdentifier: String
	var sourceURL: URL
	var imageData: Data
}

extension TranscriptMarker {
	var selectionSegment: String {
		switch self {
		case .date: "marker-date"
		case .currentSession: "marker-session"
		case .unread: "marker-unread"
		}
	}

	var isUnread: Bool {
		if case .unread = self {
			true
		} else {
			false
		}
	}
}

/** The reaction one chip in a message's details stands for.

 It is the attribute's value itself. The text storage is in-process state that
 is never archived, so a run carries the value it means rather than a delimited
 string that has to be spelled one way and parsed back the other.

 `Hashable`, because the value is boxed into an `NSAttributedString` attribute:
 the storage coalesces and compares runs through `-isEqual:` and `-hash`, and a
 Swift value that is only `Equatable` is hashed by the runtime's fallback --
 which warns on first use and collides every value of the type into one bucket.
 ``TranscriptAction`` is stored the same way and conforms for the same reason. */
struct TranscriptReactionTarget: Hashable {
	let messageIdentifier: String
	let emoji: String
}

/// What a run of transcript text stands for when it is clicked: a member's
/// name or a channel's. Like ``TranscriptReactionTarget`` it is the attribute
/// value itself, and `Hashable` for the same reason.
enum TranscriptAction: Hashable {
	case nickname(String)
	case channel(String)
}
