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
		let reload = Preferences.Logging.reloadScrollbackOnLaunch.value
		Preferences.Logging.reloadScrollbackOnLaunch.value = true
		defer { Preferences.Logging.reloadScrollbackOnLaunch.value = reload }
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString,
			isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let context = try ScrollbackDatabase.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let store = ScrollbackStore(filenameStore: ScrollbackFilenameFixture().store, makeStack: { _ in context })
		let historyClient = ScrollbackClient(
			store: .store(store),
			databaseDirectory: { directory.path },
			reportFailure: { Issue.record("\($0)") }
		)
		let client = Client(config: ClientConfig())
		let identifier = client.uniqueIdentifier
		#expect(await historyClient.retryLoading())
		let count = olderPage ? 101 : 1
		for index in 0 ..< count {
			var line = LogLine()
			line.messageBody = "row\(index)"
			line.lineType = .privateMessage
			line.receivedAt = Date(timeIntervalSince1970: Double(index + 100))
			#expect(await historyClient.writeEntry(line.historicEntry(forView: identifier)) == .accepted)
		}
		#expect(await store.saveData() == .saved)
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(client: client, in: window, inlineImageLoader: InlineImageLoader(),
		                                      scrollback: Scrollback(client: historyClient))
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
			#expect(controller.olderHistoryFailure == .invalidEntry)
		} else {
			#expect(controller.historyLoadFailure == .invalidEntry)
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
		await historyClient.prepareForTermination()
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
		let context = try ScrollbackDatabase.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let store = ScrollbackStore(filenameStore: ScrollbackFilenameFixture().store, makeStack: { _ in context })
		let client = ScrollbackClient(store: .store(store), databaseDirectory: { directory.path },
		                              reportFailure: { Issue.record("\($0)") })
		let history = Scrollback(client: client)
		var old = LogLine()
		old.messageBody = "before failed clear"
		old.lineType = .privateMessage
		old.messageIdentifier = "old-message"
		history.writeNewEntry(with: old, forView: "view")
		let request = ScrollbackFetchRequest(
			viewIdentifier: "view", kind: .newest(ascending: true, fetchLimit: 10, limitToDate: nil)
		)
		#expect(await history.fetchOutcome(request).entries.map(\.uniqueIdentifier) == [old.uniqueIdentifier])
		#expect(await client.saveData() == .saved)
		history.writeNewEntry(with: old, forView: "other-view")
		let otherRequest = ScrollbackFetchRequest(
			viewIdentifier: "other-view", kind: .newest(ascending: true, fetchLimit: 10, limitToDate: nil)
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
		#expect(history.containsMessageIdentifier("old-message", forView: "view"))

		var newer = LogLine()
		newer.messageBody = "arrived after failed clear"
		newer.lineType = .privateMessage
		history.writeNewEntry(with: newer, forView: "view")
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
		#expect(!history.containsMessageIdentifier("old-message", forView: "view"))
		#expect(try history.recovery.deletionFailures == ["other-view": #require(failures["other-view"])])
		#expect(history.recovery.localMessage != nil)
		#expect(await history.fetchOutcome(otherRequest).entries.count == 1)
		await history.removeHistory(forView: "other-view", forget: true).value
		#expect(await history.fetchOutcome(otherRequest).entries.isEmpty)
		#expect(history.recovery.deletionFailures.isEmpty)
		#expect(history.recovery.localMessage == nil)
		#expect(await client.prepareForTermination() == .saved)
		try await ScrollbackFixture.close(context)
	}

	private func setSession(_ value: Int?, context: NSManagedObjectContext, view: String) async throws {
		try await context.perform {
			let request = NSFetchRequest<NSManagedObject>(entityName: ScrollbackDatabase.entityName)
			request.predicate = NSPredicate(
				format: "%K == %@",
				ScrollbackAttribute.logLineViewIdentifier.rawValue,
				view
			)
			request.sortDescriptors = [NSSortDescriptor(
				key: ScrollbackAttribute.entryCreationDate.rawValue,
				ascending: true
			)]
			request.fetchLimit = 1
			let row = try #require(context.fetch(request).first)
			row.setValue(value.map(NSNumber.init(value:)), forKey: ScrollbackAttribute.sessionIdentifier.rawValue)
		}
	}
}
