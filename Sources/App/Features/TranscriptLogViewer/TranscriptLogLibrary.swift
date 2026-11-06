// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// One conversation's folder of daily transcripts.
nonisolated struct TranscriptLogConversation: Identifiable, Hashable, Sendable {
	/// The folder's path under the transcript folder, which is unique across
	/// connections and kinds.
	let id: String
	let kind: TranscriptKind
	/// The folder name: the conversation's name as the writer spelled it. A
	/// console has no name of its own.
	let name: String
	let directory: URL
	/// The days with a transcript, newest first.
	let days: [TranscriptDay]

	func file(for day: TranscriptDay) -> URL {
		directory.appendingPathComponent(day.filename)
	}
}

/// One connection's folder and the conversations logged under it.
nonisolated struct TranscriptLogServer: Identifiable, Hashable, Sendable {
	let id: String
	let folder: TranscriptServerFolder
	let directory: URL
	let conversations: [TranscriptLogConversation]
}

/// One line of a transcript file, identified by where it starts in the file so
/// the identity survives earlier lines being loaded in front of it.
nonisolated struct TranscriptLogLine: Identifiable, Hashable, Sendable {
	let id: Int
	let text: String

	/// The lines of `data`, which begins `baseOffset` bytes into its file. A
	/// final newline ends the last line rather than starting an empty one, and
	/// a carriage return left by another writer is not part of the text.
	static func lines(in data: Data, baseOffset: Int) -> [Self] {
		var result: [Self] = []
		var cursor = data.startIndex
		while cursor < data.endIndex {
			let newline = data[cursor...].firstIndex(of: 0x0A) ?? data.endIndex
			result.append(Self(offset: baseOffset + (cursor - data.startIndex), bytes: data[cursor ..< newline]))
			cursor = newline < data.endIndex ? newline + 1 : data.endIndex
		}

		return result
	}

	init(offset: Int, bytes: Data) {
		id = offset
		var trimmed = [UInt8](bytes)
		if trimmed.last == 0x0D {
			trimmed.removeLast()
		}
		// A line that is not valid UTF-8 is still shown, byte for byte, rather than dropped.
		text = String(bytes: trimmed, encoding: .utf8) ?? String(bytes: trimmed, encoding: .isoLatin1) ?? ""
	}
}

/// The end of a transcript file, as far back as was asked for.
nonisolated struct TranscriptLogChunk: Sendable {
	let lines: [TranscriptLogLine]
	/// Where the first line starts, so the next request can end there.
	let startOffset: Int
	let totalBytes: Int

	var hasEarlier: Bool {
		startOffset > 0
	}
}

/// Where a search found its text: the start of each matching line.
nonisolated struct TranscriptLogSearchResult: Sendable, Equatable {
	var offsets: [Int] = []
	/// Whether the search stopped at its limit with more of the file unread.
	var isTruncated = false
}

/** Reads the transcripts the application has written.

 A value over the transcript folder, holding nothing else: every call opens what
 it needs and closes it, so there is no state to guard and the work runs off the
 main actor. The folder's security-scoped access is held by
 ``ApplicationPaths``, which is why this takes only its URL. Nothing here
 follows a symbolic link, so a link planted in the folder cannot lead a read out
 of it. */
nonisolated struct TranscriptLogLibrary: Sendable {
	/// How much of a file one read takes, from its end.
	static let chunkBytes = 512 * 1024
	/// The most one read takes, however far back it was asked to reach.
	static let maximumChunkBytes = 16 * 1024 * 1024
	/// How many matching lines a search keeps.
	static let maximumMatches = 5000
	private static let searchBlockBytes = 1024 * 1024

	let root: URL

	/// Every connection, conversation and day under the folder.
	@concurrent
	func index() async -> [TranscriptLogServer] {
		let fileManager = FileManager.default
		var servers: [TranscriptLogServer] = []
		for serverURL in Self.subdirectories(of: root, using: fileManager) {
			let folder = TranscriptServerFolder(folderName: serverURL.lastPathComponent)
			var conversations: [TranscriptLogConversation] = []
			for kind in TranscriptKind.allCases {
				let kindURL = serverURL.appendingPathComponent(kind.folderName, isDirectory: true)
				let folders = kind == .console ? [kindURL] : Self.subdirectories(of: kindURL, using: fileManager)
				for url in folders {
					let days = Self.days(in: url, using: fileManager)
					guard days.isEmpty == false else { continue }
					conversations.append(TranscriptLogConversation(
						id: "\(serverURL.lastPathComponent)/\(kind.folderName)/\(kind == .console ? "" : url.lastPathComponent)",
						kind: kind,
						name: kind == .console ? "" : url.lastPathComponent,
						directory: url,
						days: days
					))
				}
			}
			guard conversations.isEmpty == false else { continue }
			conversations.sort(by: Self.isOrderedBefore)
			servers.append(TranscriptLogServer(
				id: serverURL.lastPathComponent,
				folder: folder,
				directory: serverURL,
				conversations: conversations
			))
		}

		return servers.sorted { $0.folder.name.localizedStandardCompare($1.folder.name) == .orderedAscending }
	}

	/** The part of `url` that ends at `end`, or at the end of the file.

	 Starts on a line boundary so no line is cut. `target` asks for the read to
	 reach back at least that far, for a search result that is earlier than what
	 is loaded; the read is still bounded by ``maximumChunkBytes``. */
	@concurrent
	func readChunk(of url: URL, before end: Int? = nil, reachingBack target: Int? = nil) async throws -> TranscriptLogChunk {
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }

		let total = try Int(handle.seekToEnd())
		let upperBound = min(max(end ?? total, 0), total)
		let wanted = max(Self.chunkBytes, upperBound - (target ?? upperBound))
		var start = max(upperBound - min(wanted, Self.maximumChunkBytes), 0)

		/* One byte more than asked for is read, to see whether the first byte
		 asked for begins a line. Without it a read that happens to start on a
		 line boundary would drop that line as if it had been cut. */
		let readStart = max(start - 1, 0)
		try handle.seek(toOffset: UInt64(readStart))
		var data = try handle.read(upToCount: upperBound - readStart) ?? Data()
		if start > 0 {
			if data.first == 0x0A {
				data = Data(data.dropFirst())
			} else if let newline = data.firstIndex(of: 0x0A) {
				/* The read began in the middle of a line, so that line is the
				 previous chunk's to show. */
				data = Data(data[(newline + 1)...])
				start = readStart + newline + 1
			} else {
				/* A single line longer than the read: show what there is. */
				data = Data(data.dropFirst())
			}
		}

		return TranscriptLogChunk(
			lines: TranscriptLogLine.lines(in: data, baseOffset: start),
			startOffset: start,
			totalBytes: total
		)
	}

	/// The lines of `url` that contain `query`, ignoring case and diacritics.
	@concurrent
	func search(_ query: String, in url: URL) async throws -> TranscriptLogSearchResult {
		var result = TranscriptLogSearchResult()
		guard query.isEmpty == false else { return result }

		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }

		var buffer = Data()
		var bufferOffset = 0
		func scan(_ line: TranscriptLogLine) -> Bool {
			guard line.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
				return true
			}
			guard result.offsets.count < Self.maximumMatches else {
				result.isTruncated = true
				return false
			}
			result.offsets.append(line.id)
			return true
		}

		while let block = try handle.read(upToCount: Self.searchBlockBytes), block.isEmpty == false {
			try Task.checkCancellation()
			buffer.append(block)
			var cursor = 0
			while let newline = buffer[cursor...].firstIndex(of: 0x0A) {
				let line = TranscriptLogLine(offset: bufferOffset + cursor, bytes: buffer[cursor ..< newline])
				guard scan(line) else { return result }
				cursor = newline + 1
			}
			buffer = Data(buffer[cursor...])
			bufferOffset += cursor
		}
		if buffer.isEmpty == false {
			_ = scan(TranscriptLogLine(offset: bufferOffset, bytes: buffer))
		}

		return result
	}

	private static func isOrderedBefore(_ lhs: TranscriptLogConversation, _ rhs: TranscriptLogConversation) -> Bool {
		let order = TranscriptKind.allCases
		let lhsRank = order.firstIndex(of: lhs.kind) ?? 0
		let rhsRank = order.firstIndex(of: rhs.kind) ?? 0
		if lhsRank != rhsRank {
			return lhsRank < rhsRank
		}
		return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
	}

	private static func subdirectories(of url: URL, using fileManager: FileManager) -> [URL] {
		let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
		let contents = (try? fileManager.contentsOfDirectory(
			at: url,
			includingPropertiesForKeys: keys,
			options: [.skipsHiddenFiles]
		)) ?? []

		return contents.filter { entry in
			let values = try? entry.resourceValues(forKeys: Set(keys))
			return values?.isDirectory == true && values?.isSymbolicLink != true
		}
	}

	private static func days(in url: URL, using fileManager: FileManager) -> [TranscriptDay] {
		let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
		let contents = (try? fileManager.contentsOfDirectory(
			at: url,
			includingPropertiesForKeys: keys,
			options: [.skipsHiddenFiles]
		)) ?? []

		return contents
			.filter { entry in
				let values = try? entry.resourceValues(forKeys: Set(keys))
				return values?.isRegularFile == true && values?.isSymbolicLink != true
			}
			.compactMap { TranscriptDay(filename: $0.lastPathComponent) }
			.sorted(by: >)
	}
}
