/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CoreData
@testable import Glasstual
import Testing

private nonisolated struct RecoveryFilename: HistoricLogFilenameStoring { // nonisolated: value
	var databaseFilename: String? {
		get { "history.sqlite" }
		nonmutating set { Issue.record("Recovery renamed the database: \(newValue ?? "nil")") }
	}
}

@MainActor
@Suite("Visible history recovery", .serialized)
struct LogControllerHistoryRecoveryTests {
	@Test(
		"The UI retry action repairs initial and older-page failures without deleting history",
		arguments: [false, true]
	)
	func retrySameDatabase(olderPage: Bool) async throws {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		let reload = Preferences.Logging.reloadScrollbackOnLaunch.value
		Preferences.Logging.loadHistoryLazily.value = false
		Preferences.Logging.reloadScrollbackOnLaunch.value = true
		defer {
			Preferences.Logging.loadHistoryLazily.value = lazy
			Preferences.Logging.reloadScrollbackOnLaunch.value = reload
		}
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString,
			isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let context = try HistoricLogDatabase.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let store = HistoricLogStore(filenameStore: RecoveryFilename(), makeStack: { _ in context })
		let historyClient = HistoricLogClient(
			store: store,
			databaseDirectory: { directory.path },
			reportFailure: { Issue.record("\($0)") }
		)
		let client = IRCClient(config: ClientConfig())
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
		let controller = LogController(client: client, in: window, inlineImageLoader: NativeInlineImageLoader(),
		                               historicLog: LogControllerHistoricLogFile(client: historyClient))
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
		#expect(await store.fetchEntries(forView: identifier, ascending: true, fetchLimit: 1000, limitToDate: nil)
			.count == count)
		#expect(controller.historicLogMutationTask == nil)
		controller.tearDown(.preservingRemoval)
		await historyClient.prepareForTermination()
	}

	@Test("Retry saves newer messages but leaves failed deletion visible until an explicit clear succeeds",
	      arguments: [false, true])
	func retryDoesNotRepeatFailedDeletion(forget: Bool) async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString, isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let context = try HistoricLogDatabase.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let store = HistoricLogStore(filenameStore: RecoveryFilename(), makeStack: { _ in context })
		let client = HistoricLogClient(store: store, databaseDirectory: { directory.path },
		                               reportFailure: { Issue.record("\($0)") })
		let history = LogControllerHistoricLogFile(client: client)
		var old = LogLine()
		old.messageBody = "before failed clear"
		old.lineType = .privateMessage
		old.messageIdentifier = "old-message"
		history.writeNewEntry(with: old, forView: "view")
		let request = HistoricLogFetchRequest(
			viewIdentifier: "view", kind: .newest(ascending: true, fetchLimit: 10, limitToDate: nil)
		)
		#expect(await history.fetchOutcome(request).entries.map(\.uniqueIdentifier) == [old.uniqueIdentifier])
		#expect(await client.saveData() == .saved)
		history.writeNewEntry(with: old, forView: "other-view")
		let otherRequest = HistoricLogFetchRequest(
			viewIdentifier: "other-view", kind: .newest(ascending: true, fetchLimit: 10, limitToDate: nil)
		)
		#expect(await history.fetchOutcome(otherRequest).entries.count == 1)
		try await setSession(nil, context: context, view: "view")
		if forget {
			await history.forgetView("view").value
		} else {
			await history.resetData(forView: "view").value
		}
		await history.forgetView("other-view").value
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
			.contains(String(localized: .TranscriptHistory.deletionNotRepeated)) == true)
		#expect(await Set(history.fetchOutcome(request).entries.map(\.uniqueIdentifier)) ==
			[old.uniqueIdentifier, newer.uniqueIdentifier])
		#expect(await history.fetchOutcome(otherRequest).entries.map(\.uniqueIdentifier) == [old.uniqueIdentifier])

		await history.resetData(forView: "view").value
		#expect(await history.fetchOutcome(request).entries.isEmpty)
		#expect(!history.containsMessageIdentifier("old-message", forView: "view"))
		#expect(try history.recovery.deletionFailures == ["other-view": #require(failures["other-view"])])
		#expect(history.recovery.localMessage != nil)
		#expect(await history.fetchOutcome(otherRequest).entries.count == 1)
		await history.forgetView("other-view").value
		#expect(await history.fetchOutcome(otherRequest).entries.isEmpty)
		#expect(history.recovery.deletionFailures.isEmpty)
		#expect(history.recovery.localMessage == nil)
		#expect(await client.prepareForTermination() == .saved)
	}

	private func setSession(_ value: Int?, context: NSManagedObjectContext, view: String) async throws {
		try await context.perform {
			let request = NSFetchRequest<NSManagedObject>(entityName: HistoricLogDatabase.entityName)
			request.predicate = NSPredicate(
				format: "%K == %@",
				HistoricLogAttribute.logLineViewIdentifier.rawValue,
				view
			)
			request.sortDescriptors = [NSSortDescriptor(
				key: HistoricLogAttribute.entryCreationDate.rawValue,
				ascending: true
			)]
			request.fetchLimit = 1
			let row = try #require(context.fetch(request).first)
			row.setValue(value.map(NSNumber.init(value:)), forKey: HistoricLogAttribute.sessionIdentifier.rawValue)
		}
	}
}
