// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

/// A request for the log text to scroll to a line. The serial makes asking for
/// the same line twice a new request, so stepping onto a match already on
/// screen still moves the view.
struct TranscriptLogScrollRequest: Equatable {
	let lineID: Int
	let serial: Int
}

/** What the transcript log window is showing: the logs under the folder, the
 one chosen, as much of it as has been read, and a search through it.

 Reading and searching run in ``TranscriptLogLibrary`` off the main actor; this
 holds the results. A log is read from its end, a chunk at a time, because the
 newest lines are what is wanted and a year of a busy channel is not something
 to hold whole. */
@Observable
final class TranscriptLogViewerModel {
	enum Phase: Equatable {
		/// No transcript folder has been chosen, or it cannot be reached.
		case noFolder
		case loading
		case ready
	}

	private(set) var phase: Phase = .loading
	private(set) var servers: [TranscriptLogServer] = []
	private(set) var selectedConversationID: String?
	private(set) var selectedDay: TranscriptDay?

	private(set) var lines: [TranscriptLogLine] = []
	private(set) var startOffset = 0
	private(set) var totalBytes = 0
	private(set) var isLoadingLog = false
	private(set) var logCouldNotBeRead = false

	var searchText = ""
	private(set) var matchOffsets: [Int] = []
	private(set) var matchesAreTruncated = false
	private(set) var currentMatchIndex: Int?
	private(set) var scrollRequest: TranscriptLogScrollRequest?

	@ObservationIgnored private let rootProvider: () -> URL?
	@ObservationIgnored private var library: TranscriptLogLibrary?
	@ObservationIgnored private var scrollSerial = 0

	/// - Parameter rootProvider: The transcript folder as it is now. Read on each
	///   refresh, because the user can choose another folder while the window is
	///   open.
	init(rootProvider: @escaping () -> URL? = { ApplicationPaths.transcriptFolderURL }) {
		self.rootProvider = rootProvider
	}

	var selectedConversation: TranscriptLogConversation? {
		guard let selectedConversationID else { return nil }
		return servers.lazy.flatMap(\.conversations).first { $0.id == selectedConversationID }
	}

	/// The file being read, or `nil` while nothing is chosen.
	var selectedFile: URL? {
		guard let day = selectedDay else { return nil }
		return selectedConversation?.file(for: day)
	}

	var hasEarlierLines: Bool {
		startOffset > 0
	}

	/// What Show in Finder selects: the log, else its folder, else the root.
	var revealURL: URL? {
		selectedFile ?? selectedConversation?.directory ?? rootProvider()
	}

	var hasMatches: Bool {
		matchOffsets.isEmpty == false
	}

	/// The line the current match is on.
	var currentMatchOffset: Int? {
		currentMatchIndex.map { matchOffsets[$0] }
	}

	/// Reads the folder again, keeping the selection where it still exists.
	func refresh() async {
		guard let root = rootProvider() else {
			library = nil
			servers = []
			clearLog()
			phase = .noFolder
			return
		}

		let library = TranscriptLogLibrary(root: root)
		self.library = library
		if servers.isEmpty {
			phase = .loading
		}
		servers = await library.index()
		phase = .ready

		guard let conversation = selectedConversation else {
			selectedConversationID = nil
			selectedDay = nil
			clearLog()
			return
		}
		if let selectedDay, conversation.days.contains(selectedDay) == false {
			self.selectedDay = conversation.days.first
		}
	}

	func selectConversation(id: String?) {
		guard id != selectedConversationID else { return }
		selectedConversationID = id
		selectedDay = selectedConversation?.days.first
		clearLog()
	}

	func selectDay(_ day: TranscriptDay?) {
		guard day != selectedDay else { return }
		selectedDay = day
		clearLog()
	}

	/// Reads the end of the chosen log, replacing what was showing.
	func loadSelectedLog() async {
		clearLog()
		guard let library, let url = selectedFile else { return }

		isLoadingLog = true
		defer { isLoadingLog = false }
		do {
			let chunk = try await library.readChunk(of: url)
			guard url == selectedFile else { return }
			apply(chunk)
		} catch {
			logCouldNotBeRead = true
		}
	}

	/// Reads the chunk before the first line showing and puts it in front.
	func loadEarlier() async {
		await loadEarlier(reachingBack: nil)
	}

	private func loadEarlier(reachingBack target: Int?) async {
		guard let library, let url = selectedFile, hasEarlierLines, isLoadingLog == false else { return }

		isLoadingLog = true
		defer { isLoadingLog = false }
		do {
			let chunk = try await library.readChunk(of: url, before: startOffset, reachingBack: target)
			guard url == selectedFile, chunk.startOffset < startOffset else { return }
			lines = chunk.lines + lines
			startOffset = chunk.startOffset
			totalBytes = chunk.totalBytes
		} catch {
			logCouldNotBeRead = true
		}
	}

	/// Searches the whole file, not only what is loaded, and moves to the match
	/// nearest the end, which is the newest.
	func search() async {
		matchOffsets = []
		matchesAreTruncated = false
		currentMatchIndex = nil
		let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard query.isEmpty == false, let library, let url = selectedFile else { return }

		do {
			let result = try await library.search(query, in: url)
			guard url == selectedFile, query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else {
				return
			}
			matchOffsets = result.offsets
			matchesAreTruncated = result.isTruncated
			if result.offsets.isEmpty == false {
				await moveToMatch(result.offsets.count - 1)
			}
		} catch {
			/* A cancelled search is replaced by the next one; one that failed to
			 read leaves no matches, and the log itself reports its own failure. */
		}
	}

	func nextMatch() async {
		guard let currentMatchIndex else { return }
		await moveToMatch((currentMatchIndex + 1) % matchOffsets.count)
	}

	func previousMatch() async {
		guard let currentMatchIndex else { return }
		await moveToMatch((currentMatchIndex + matchOffsets.count - 1) % matchOffsets.count)
	}

	private func moveToMatch(_ index: Int) async {
		guard matchOffsets.indices.contains(index) else { return }
		currentMatchIndex = index
		let offset = matchOffsets[index]
		if offset < startOffset {
			await loadEarlier(reachingBack: offset)
		}
		guard offset >= startOffset else { return }
		scrollSerial += 1
		scrollRequest = TranscriptLogScrollRequest(lineID: offset, serial: scrollSerial)
	}

	private func apply(_ chunk: TranscriptLogChunk) {
		lines = chunk.lines
		startOffset = chunk.startOffset
		totalBytes = chunk.totalBytes
	}

	private func clearLog() {
		lines = []
		startOffset = 0
		totalBytes = 0
		logCouldNotBeRead = false
		matchOffsets = []
		matchesAreTruncated = false
		currentMatchIndex = nil
		scrollRequest = nil
	}
}
