// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CoreData
@testable import Glasstual
import Testing

@MainActor
@Suite("Visible history recovery", .serialized)
struct TranscriptControllerHistoryRecoveryTests {
	@Test(
		"The UI retry action repairs initial and older-page failures without deleting history",
		arguments: [false, true]
	)
	func retrySameDatabase(olderPage: Bool) async throws {
		let reload = SettingsKeys.Logging.reloadScrollbackOnLaunch.value
		SettingsKeys.Logging.reloadScrollbackOnLaunch.value = true
		defer { SettingsKeys.Logging.reloadScrollbackOnLaunch.value = reload }
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString,
			isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let context = try ScrollbackQueries.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture().store, makeStack: { _ in context })
		let historySession = ScrollbackSession(
			store: store,
			databaseDirectory: { directory.path },
			reportFailure: { Issue.record("\($0)") }
		)
		let session = ServerSession(config: ServerConfig())
		let identifier = session.uniqueIdentifier
		#expect(await historySession.retryLoading())
		let count = olderPage ? 101 : 1
		for index in 0 ..< count {
			var line = ChatLine()
			line.messageBody = "row\(index)"
			line.lineType = .privateMessage
			line.receivedAt = Date(timeIntervalSince1970: Double(index + 100))
			#expect(await historySession.writeEntry(line.scrollbackEntry(forView: identifier)) == .accepted)
		}
		#expect(await store.saveData() == .saved)
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(session: session, in: window, inlineImageLoader: InlineImageLoader(),
		                                      scrollback: Scrollback(session: historySession))
		controller.loadsHistoryLazily = { false }
		if !olderPage {
			try await setSession(nil, context: context, view: identifier)
		}
		let view = controller.ensureBackingView()
		await controller.drainRenderJobs()
		if olderPage {
			try await setSession(nil, context: context, view: identifier)
			controller.loadOlderHistory()
			await controller.drainRenderJobs()
			#expect(controller.historyRecovery.olderFailure == .invalidEntry)
		} else {
			#expect(controller.historyRecovery.initialFailure == .invalidEntry)
		}
		#expect(controller.historyRecovery.localMessage != nil)
		try await setSession(1, context: context, view: identifier)
		controller.retryHistory()
		await controller.historyRetryTask?.value
		#expect(!controller.historyRecovery.isRetrying)
		#expect(controller.historyRecovery.localMessage == nil)
		#expect(view.displayedLines.contains { $0.body.plainText == "row0" })
		#expect(await store.fetchOutcome(.newestEntries(forView: identifier, fetchLimit: 1000)).entries
			.count == count)
		#expect(controller.scrollbackMutationTask == nil)
		controller.tearDown(.preservingRemoval)
		await historySession.prepareForTermination()
		try await ScrollbackFixture.close(context)
	}

	@Test("Retry saves newer messages but leaves failed deletion visible until an explicit clear succeeds",
	      arguments: [false, true])
	func retryDoesNotRepeatFailedDeletion(forget: Bool) async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString, isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let context = try ScrollbackQueries.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture().store, makeStack: { _ in context })
		let session = ScrollbackSession(store: store, databaseDirectory: { directory.path },
		                                reportFailure: { Issue.record("\($0)") })
		let history = Scrollback(session: session)
		var old = ChatLine()
		old.messageBody = "before failed clear"
		old.lineType = .privateMessage
		old.messageIdentifier = "old-message"
		history.writeNewEntry(old.scrollbackEntry(forView: "view"), for: old)
		let request = ScrollbackFetchRequest(
			viewIdentifier: "view", kind: .rowPage(before: nil, fetchLimit: 10, limitToDate: nil)
		)
		#expect(await history.fetchOutcome(request).entries.map(\.uniqueIdentifier) == [old.uniqueIdentifier])
		#expect(await session.saveData() == .saved)
		history.writeNewEntry(old.scrollbackEntry(forView: "other-view"), for: old)
		let otherRequest = ScrollbackFetchRequest(
			viewIdentifier: "other-view", kind: .rowPage(before: nil, fetchLimit: 10, limitToDate: nil)
		)
		#expect(await history.fetchOutcome(otherRequest).entries.count == 1)
		try await setSession(nil, context: context, view: "view")
		if forget {
			await history.removeHistory(forView: "view", forget: true).value
		} else {
			await history.removeHistory(forView: "view", forget: false).value
		}
		await history.removeHistory(forView: "other-view", forget: true).value
		let failures = history.recovery.deletionFailures
		#expect(Set(failures.keys) == ["view", "other-view"])
		#expect(history.recovery.localMessage != nil)
		#expect(history.duplicates.containsMessageIdentifier("old-message", forView: "view"))

		var newer = ChatLine()
		newer.messageBody = "arrived after failed clear"
		newer.lineType = .privateMessage
		history.writeNewEntry(newer.scrollbackEntry(forView: "view"), for: newer)
		// Drain the write while the original row is still invalid, then repair the fixture.
		_ = await history.fetchOutcome(request)
		try await setSession(1, context: context, view: "view")
		#expect(await history.retryLoading())
		#expect(history.recovery.storageFailure == nil)
		#expect(history.recovery.deletionFailures == failures)
		#expect(history.recovery.localMessage?
			.contains(String(localized: .Transcript.deletionNotRepeated)) == true)
		#expect(await Set(history.fetchOutcome(request).entries.map(\.uniqueIdentifier)) ==
			[old.uniqueIdentifier, newer.uniqueIdentifier])
		#expect(await history.fetchOutcome(otherRequest).entries.map(\.uniqueIdentifier) == [old.uniqueIdentifier])

		await history.removeHistory(forView: "view", forget: false).value
		#expect(await history.fetchOutcome(request).entries.isEmpty)
		#expect(!history.duplicates.containsMessageIdentifier("old-message", forView: "view"))
		#expect(try history.recovery.deletionFailures == ["other-view": #require(failures["other-view"])])
		#expect(history.recovery.localMessage != nil)
		#expect(await history.fetchOutcome(otherRequest).entries.count == 1)
		await history.removeHistory(forView: "other-view", forget: true).value
		#expect(await history.fetchOutcome(otherRequest).entries.isEmpty)
		#expect(history.recovery.deletionFailures.isEmpty)
		#expect(history.recovery.localMessage == nil)
		#expect(await session.prepareForTermination() == .saved)
		try await ScrollbackFixture.close(context)
	}

	private func setSession(_ value: Int?, context: NSManagedObjectContext, view: String) async throws {
		try await context.perform {
			let request = NSFetchRequest<NSManagedObject>(entityName: ScrollbackQueries.entityName)
			request.predicate = NSPredicate(
				format: "%K == %@",
				ScrollbackAttribute.viewID.rawValue,
				view
			)
			request.sortDescriptors = [NSSortDescriptor(
				key: ScrollbackAttribute.createdAt.rawValue,
				ascending: true
			)]
			request.fetchLimit = 1
			let row = try #require(context.fetch(request).first)
			row.setValue(value.map(NSNumber.init(value:)), forKey: ScrollbackAttribute.sessionID.rawValue)
		}
	}
}
