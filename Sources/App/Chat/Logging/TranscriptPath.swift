// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The folder a transcript is filed under, by what kind of conversation it is.

 The strings are folder names on the user's disk, so they stay as they are
 spelled there whatever the Swift vocabulary around them becomes. */
nonisolated enum TranscriptFolderName {
	static let console = "Console"
	static let channel = "Channels"
	static let direct = "Queries"
}

/** What kind of conversation a transcript folder holds, read back from the
 folder's name.

 The inverse of the folders ``TranscriptPath`` writes, for the log viewer: the
 names are the ones on disk, shared with the writer so the two cannot drift. */
nonisolated enum TranscriptKind: CaseIterable, Sendable {
	case console
	case channel
	case direct

	init?(folderName: String) {
		guard let kind = Self.allCases.first(where: { $0.folderName == folderName }) else { return nil }
		self = kind
	}

	var folderName: String {
		switch self {
		case .console: TranscriptFolderName.console
		case .channel: TranscriptFolderName.channel
		case .direct: TranscriptFolderName.direct
		}
	}
}

/** The connection folder a transcript is filed under: `Name (abcde)`, the
 connection's name and the first five characters of its identifier. */
nonisolated struct TranscriptServerFolder: Hashable, Sendable {
	let name: String
	/// The identifier prefix, empty when the folder was not written by this
	/// application and carries none.
	let identifier: String

	init(folderName: String) {
		guard folderName.hasSuffix(")"),
		      let open = folderName.range(of: " (", options: .backwards)
		else {
			name = folderName
			identifier = ""
			return
		}

		let candidate = folderName[open.upperBound ..< folderName.index(before: folderName.endIndex)]
		guard candidate.isEmpty == false, candidate.count <= 5, candidate.allSatisfy(\.isHexDigit) else {
			name = folderName
			identifier = ""
			return
		}

		name = String(folderName[..<open.lowerBound])
		identifier = String(candidate)
	}
}

/** The day a transcript file holds, from its `YYYY-MM-DD.txt` name.

 Calendar numbers rather than a `Date`: the writer chose the day in the time
 zone it was written in, and the name is the only record of which. */
nonisolated struct TranscriptDay: Hashable, Comparable, Sendable {
	let year: Int
	let month: Int
	let day: Int

	init(year: Int, month: Int, day: Int) {
		self.year = year
		self.month = month
		self.day = day
	}

	/// `nil` for a file that is not a day's transcript.
	init?(filename: String) {
		let stem = filename.hasSuffix(".txt") ? String(filename.dropLast(4)) : ""
		let parts = stem.split(separator: "-", omittingEmptySubsequences: false)
		guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
		      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
		      (1 ... 12).contains(month), (1 ... 31).contains(day)
		else { return nil }

		self.init(year: year, month: month, day: day)
	}

	/// The file name the writer gives this day.
	var filename: String {
		String(format: "%04d-%02d-%02d.txt", year, month, day)
	}

	/// The day as a date at noon in `calendar`, for display.
	func date(in calendar: Calendar = .current) -> Date? {
		calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
	}

	static func < (lhs: Self, rhs: Self) -> Bool {
		if lhs.year != rhs.year {
			return lhs.year < rhs.year
		}
		if lhs.month != rhs.month {
			return lhs.month < rhs.month
		}
		return lhs.day < rhs.day
	}
}

/** Where an item's transcript is written.

 A pure function of the item: one folder per connection, then one per kind of
 conversation, then one per conversation. Nothing here opens a file, so the
 layout can be asserted without a disk. */
enum TranscriptPath {
	/// The path under the user's transcript folder, or `nil` for an item whose
	/// lines are never written — a console view, or one with no session left.
	static func relative(for item: ChatItem) -> String? {
		let conversation = item.associatedConversation
		if let conversation, conversation.isConsole {
			return nil
		}
		guard let session = item.associatedSession else { return nil }

		let sessionIdentifier = String(session.uniqueIdentifier.prefix(5))
		let sessionName = "\(session.name) (\(sessionIdentifier))".safeFilename
		guard let conversation else {
			return "/\(sessionName)/\(TranscriptFolderName.console)/"
		}
		let conversationName = conversation.name.safeFilename
		if conversation.isChannel {
			return "/\(sessionName)/\(TranscriptFolderName.channel)/\(conversationName)/"
		}
		if conversation.isDirect || conversation.isDirectChat {
			return "/\(sessionName)/\(TranscriptFolderName.direct)/\(conversationName)/"
		}
		return nil
	}

	/// The same path under the folder the user chose, when one has been chosen.
	static func write(for item: ChatItem) -> String? {
		guard let sourcePath = ApplicationPaths.transcriptFolder else { return nil }
		return write(for: item, relativeTo: sourcePath)
	}

	static func write(for item: ChatItem, relativeTo sourcePath: String) -> String? {
		guard let relativePath = relative(for: item) else { return nil }
		return (sourcePath as NSString).appendingPathComponent(relativePath)
	}
}
