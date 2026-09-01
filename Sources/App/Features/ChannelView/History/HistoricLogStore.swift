/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2016 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CoreData
import Foundation
import os

/// Owns the historic log Core Data stack, per-view contexts, line counts,
/// resize timers, and save scheduling in one isolation domain.
actor HistoricLogStore {
	typealias DeletionHandler = @Sendable ([String], String) async -> Void

	/// Everything the store knows about one log view. The context is the only
	/// thing Core Data owns; the counts are kept here so a write does not have
	/// to re-count the table on every line.
	private struct ViewState {
		let context: NSManagedObjectContext
		var totalLineCount: UInt = 0
		var newestIdentifier: UInt = 0
		var resizeTask: Task<Void, Never>?
	}

	private var rootContext: NSManagedObjectContext?
	private var databaseURL: URL?
	private var databaseDirectoryURL: URL?

	private var views: [String: ViewState] = [:]
	private var maximumLineCount: UInt = 100

	private var saveTask: Task<Void, Never>?
	/// Where the name of the database file is kept between launches.
	///
	/// Production uses the typed preference; tests inject isolated storage.
	private let filenameStore: any HistoricLogFilenameStoring
	private let deletionHandler: DeletionHandler

	/// How long the store waits between unattended saves.
	private static let saveInterval = Duration.seconds(120)

	/// The widest random delay before a view over its line cap is truncated.
	/// Spreading the work keeps a hundred views from resizing in lockstep.
	private static let maximumResizeDelay: UInt32 = 1800

	init(
		filenameStore: any HistoricLogFilenameStoring,
		deletionHandler: @escaping DeletionHandler = { _, _ in }
	) {
		self.filenameStore = filenameStore
		self.deletionHandler = deletionHandler
	}

	func close() async {
		cancelScheduledSave()
		await saveAllContexts(cancellingResize: true)
		views.removeAll()
		rootContext = nil
	}

	// MARK: - Database

	func openDatabase(inDirectory databaseDirectory: String) -> Bool {
		databaseDirectoryURL = URL(fileURLWithPath: databaseDirectory, isDirectory: true)

		setDatabasePath()

		guard let databaseURL else { return false }

		HistoricLogDatabase.logger.info("Opening database at path: \(databaseURL.path, privacy: .public)")

		var context = HistoricLogDatabase.makeStack(at: databaseURL)

		if context == nil {
			/* A store that cannot be opened is almost always a corrupt file
			 from an older build. Start a fresh one rather than leave the view
			 without any history at all. */
			_ = resetDatabaseFilename()

			setDatabasePath()

			context = self.databaseURL.flatMap { HistoricLogDatabase.makeStack(at: $0) }
		}

		guard let context else { return false }

		rootContext = context

		rescheduleSave()

		return true
	}

	func setMaximumLineCount(_ maximumLineCount: UInt) {
		// A malformed stored value must not destabilize history.
		guard maximumLineCount > 0 else {
			HistoricLogDatabase.logger.error("Ignoring a request to set the maximum line count to zero")

			return
		}

		self.maximumLineCount = maximumLineCount
	}

	private func setDatabasePath() {
		databaseURL = databaseDirectoryURL?.appendingPathComponent(databaseSaveFilename(), isDirectory: false)
	}

	private func databaseSaveFilename() -> String {
		filenameStore.databaseFilename ?? resetDatabaseFilename()
	}

	private func resetDatabaseFilename() -> String {
		let filename = "logControllerHistoricLog_\(UUID().uuidString).sqlite"

		filenameStore.databaseFilename = filename

		return filename
	}

	// MARK: - Views

	/// The context for a view, created on first use. The bookkeeping entry is
	/// installed before the counts are read so a second request arriving during
	/// that await joins the same context instead of building a rival one.
	private func context(forView viewIdentifier: String) async -> NSManagedObjectContext? {
		if let existing = views[viewIdentifier] {
			return existing.context
		}

		guard let rootContext else {
			HistoricLogDatabase.logger
				.error("Requested context for \(viewIdentifier, privacy: .public) before the database was opened")

			return nil
		}

		let context = HistoricLogDatabase.makeViewContext(parent: rootContext)

		views[viewIdentifier] = ViewState(context: context)

		let counts = await context.perform {
			(
				lineCount: HistoricLogDatabase.lineCount(in: context, viewIdentifier: viewIdentifier),
				newestIdentifier: HistoricLogDatabase.newestIdentifier(in: context, viewIdentifier: viewIdentifier)
			)
		}

		/* The view may have been forgotten while the counts were being read. */
		guard views[viewIdentifier]?.context === context else {
			return views[viewIdentifier]?.context
		}

		views[viewIdentifier]?.totalLineCount = counts.lineCount
		views[viewIdentifier]?.newestIdentifier = counts.newestIdentifier

		HistoricLogDatabase.logger.debug(
			"Context created for \(viewIdentifier, privacy: .public), line count: \(counts.lineCount), newest identifier: \(counts.newestIdentifier)"
		)

		return context
	}

	func forgetView(_ viewIdentifier: String) async {
		HistoricLogDatabase.logger.debug("Forgetting view: \(viewIdentifier, privacy: .public)")

		guard let context = await context(forView: viewIdentifier) else { return }

		cancelResize(forView: viewIdentifier)

		let result = await context.perform {
			let result = HistoricLogDatabase.delete(.everything, in: context, viewIdentifier: viewIdentifier)

			context.reset()

			return result
		}

		views.removeValue(forKey: viewIdentifier)

		await reportDeletion(result, inView: viewIdentifier)
	}

	func resetData(forView viewIdentifier: String) async {
		HistoricLogDatabase.logger.debug("Resetting the contents of view: \(viewIdentifier, privacy: .public)")

		guard let context = await context(forView: viewIdentifier) else { return }

		cancelResize(forView: viewIdentifier)

		let result = await context.perform {
			let result = HistoricLogDatabase.delete(.everything, in: context, viewIdentifier: viewIdentifier)

			context.reset()

			return result
		}

		views[viewIdentifier]?.totalLineCount = 0

		await reportDeletion(result, inView: viewIdentifier)
	}

	// MARK: - Writing

	func writeLogLine(_ logLine: HistoricLogEntry) async {
		let viewIdentifier = logLine.viewIdentifier

		guard let context = await context(forView: viewIdentifier) else { return }

		let entryIdentifier = incrementNewestIdentifier(forView: viewIdentifier)

		await context.perform {
			HistoricLogDatabase.insert(logLine, in: context, entryIdentifier: entryIdentifier)
		}

		scheduleResize(forView: viewIdentifier)
	}

	private func incrementNewestIdentifier(forView viewIdentifier: String) -> UInt {
		guard var state = views[viewIdentifier] else { return 0 }

		state.totalLineCount = saturatedAdd(state.totalLineCount, 1)
		state.newestIdentifier = saturatedAdd(state.newestIdentifier, 1)

		views[viewIdentifier] = state

		return state.newestIdentifier
	}

	// MARK: - Fetching

	func fetchEntries(
		forView viewIdentifier: String,
		ascending: Bool,
		fetchLimit: UInt,
		limitToDate: Date?
	) async -> [HistoricLogEntry] {
		guard let context = await context(forView: viewIdentifier) else { return [] }

		return await context.perform {
			HistoricLogDatabase.fetchEntries(
				in: context,
				viewIdentifier: viewIdentifier,
				ascending: ascending,
				fetchLimit: fetchLimit,
				limitToDate: limitToDate
			)
		}
	}

	func fetchEntries(
		forView viewIdentifier: String,
		aroundUniqueIdentifier uniqueIdentifier: String,
		beforeFetchLimit: UInt,
		afterFetchLimit: UInt,
		limitToDate: Date?
	) async -> [HistoricLogEntry] {
		guard let context = await context(forView: viewIdentifier) else { return [] }

		/* Bound the centered query to the configured scrollback capacity. */
		let fetchLimit = maximumLineCount

		return await context.perform {
			let entryIdentifier = HistoricLogDatabase.entryIdentifier(
				in: context,
				viewIdentifier: viewIdentifier,
				uniqueIdentifier: uniqueIdentifier
			)

			guard entryIdentifier != HistoricLogDatabase.missingEntryIdentifier else { return [] }

			return HistoricLogDatabase.fetchEntries(
				in: context,
				viewIdentifier: viewIdentifier,
				ascending: true,
				fetchLimit: fetchLimit,
				lowestEntryIdentifier: entryIdentifier > beforeFetchLimit ? entryIdentifier - beforeFetchLimit : 0,
				highestEntryIdentifier: saturatedAdd(entryIdentifier, afterFetchLimit),
				limitToDate: limitToDate
			)
		}
	}

	func fetchEntries(
		forView viewIdentifier: String,
		relativeTo uniqueIdentifier: String,
		direction: FetchDirection,
		fetchLimit: UInt,
		limitToDate: Date?
	) async -> [HistoricLogEntry] {
		guard fetchLimit > 0 else {
			HistoricLogDatabase.logger.error("Ignoring a fetch request with a zero fetch limit")

			return []
		}

		guard let context = await context(forView: viewIdentifier) else { return [] }

		return await context.perform {
			let entryIdentifier = HistoricLogDatabase.entryIdentifier(
				in: context,
				viewIdentifier: viewIdentifier,
				uniqueIdentifier: uniqueIdentifier
			)

			guard entryIdentifier != HistoricLogDatabase.missingEntryIdentifier else { return [] }

			let bounds: (lowest: UInt, highest: UInt) = switch direction {
			case .before:
				(
					entryIdentifier > fetchLimit ? entryIdentifier - fetchLimit : 0,
					entryIdentifier > 0 ? entryIdentifier - 1 : 0
				)
			case .after:
				(saturatedAdd(entryIdentifier, 1), saturatedAdd(entryIdentifier, fetchLimit))
			}

			return HistoricLogDatabase.fetchEntries(
				in: context,
				viewIdentifier: viewIdentifier,
				ascending: true,
				fetchLimit: fetchLimit,
				lowestEntryIdentifier: bounds.lowest,
				highestEntryIdentifier: bounds.highest,
				limitToDate: limitToDate
			)
		}
	}

	func fetchEntries(
		forView viewIdentifier: String,
		afterUniqueIdentifier uniqueIdentifierAfter: String,
		beforeUniqueIdentifier uniqueIdentifierBefore: String,
		fetchLimit: UInt
	) async -> [HistoricLogEntry] {
		guard let context = await context(forView: viewIdentifier) else { return [] }

		return await context.perform {
			let first = HistoricLogDatabase.entryIdentifier(
				in: context,
				viewIdentifier: viewIdentifier,
				uniqueIdentifier: uniqueIdentifierAfter
			)
			let second = HistoricLogDatabase.entryIdentifier(
				in: context,
				viewIdentifier: viewIdentifier,
				uniqueIdentifier: uniqueIdentifierBefore
			)

			guard
				first != HistoricLogDatabase.missingEntryIdentifier,
				second != HistoricLogDatabase.missingEntryIdentifier
			else { return [] }

			return HistoricLogDatabase.fetchEntries(
				in: context,
				viewIdentifier: viewIdentifier,
				ascending: true,
				fetchLimit: fetchLimit,
				lowestEntryIdentifier: saturatedAdd(first, 1),
				highestEntryIdentifier: second > 0 ? second - 1 : 0,
				limitToDate: nil
			)
		}
	}

	// MARK: - Saving

	func saveData() async {
		rescheduleSave()
		await saveAllContexts(cancellingResize: false)
	}

	private func saveAllContexts(cancellingResize: Bool) async {
		guard let rootContext else { return }

		HistoricLogDatabase.logger.debug("Performing save")

		for (viewIdentifier, state) in views {
			if cancellingResize {
				cancelResize(forView: viewIdentifier)
			}

			let context = state.context

			await context.perform { HistoricLogDatabase.quickSave(context) }
		}

		await rootContext.perform { HistoricLogDatabase.quickSave(rootContext) }
	}

	private func rescheduleSave() {
		cancelScheduledSave()

		saveTask = Task { [weak self] in
			while Task.isCancelled == false {
				try? await Task.sleep(for: Self.saveInterval, clock: .continuous)

				guard Task.isCancelled == false, let self else { return }

				await saveAllContexts(cancellingResize: false)
			}
		}
	}

	private func cancelScheduledSave() {
		saveTask?.cancel()
		saveTask = nil
	}

	// MARK: - Resizing

	private func scheduleResize(forView viewIdentifier: String) {
		guard let state = views[viewIdentifier],
		      state.resizeTask == nil,
		      state.totalLineCount >= maximumLineCount
		else { return }

		let delay = TimeInterval(UInt32.random(in: 0 ..< Self.maximumResizeDelay))

		views[viewIdentifier]?.resizeTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(delay), clock: .continuous)

			guard Task.isCancelled == false, let self else { return }

			await resize(viewIdentifier)
		}

		HistoricLogDatabase.logger
			.debug("Scheduled to resize \(viewIdentifier, privacy: .public) in \(delay) seconds")
	}

	private func cancelResize(forView viewIdentifier: String) {
		views[viewIdentifier]?.resizeTask?.cancel()
		views[viewIdentifier]?.resizeTask = nil
	}

	private func resize(_ viewIdentifier: String) async {
		guard let state = views[viewIdentifier] else { return }

		HistoricLogDatabase.logger.debug("Resizing view \(viewIdentifier, privacy: .public)")

		views[viewIdentifier]?.resizeTask = nil

		let context = state.context
		let lowest = state.newestIdentifier > maximumLineCount ? state.newestIdentifier - maximumLineCount : 0

		let result = await context.perform {
			HistoricLogDatabase.delete(
				.entriesBelow(entryIdentifier: lowest),
				in: context,
				viewIdentifier: viewIdentifier
			)
		}

		if let total = views[viewIdentifier]?.totalLineCount {
			views[viewIdentifier]?.totalLineCount = result.deletedCount > total ? 0 : total - result.deletedCount
		}

		await reportDeletion(result, inView: viewIdentifier)
	}

	// MARK: - Client Notifications

	private func reportDeletion(_ result: HistoricLogDatabase.DeletionResult, inView viewIdentifier: String) async {
		guard result.uniqueIdentifiers.isEmpty == false else { return }

		await deletionHandler(result.uniqueIdentifiers, viewIdentifier)
	}
}

/// Which side of a known entry a relative fetch reads.
nonisolated enum FetchDirection: Sendable { // nonisolated: value
	case before
	case after
}

/// Saturating addition. A free function so the Core Data helpers, which run
/// on a context's queue rather than on the actor, can use it too.
nonisolated func saturatedAdd(_ lhs: UInt, _ rhs: UInt) -> UInt { // nonisolated: pure
	let (result, overflow) = lhs.addingReportingOverflow(rhs)

	return overflow ? UInt.max : result
}
