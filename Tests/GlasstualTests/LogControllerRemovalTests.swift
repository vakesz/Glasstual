/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Controller removal history policy", .serialized)
struct LogControllerRemovalTests {
	@Test("Removal preserves stored rows independently of launch-reload preferences",
	      arguments: [false, true], [false, true])
	func removalPolicy(preservingLocalData: Bool, reloadScrollback: Bool) async throws {
		let previousReload = Preferences.Logging.reloadScrollbackOnLaunch.value
		let previousLazy = Preferences.Logging.loadHistoryLazily.value
		Preferences.Logging.reloadScrollbackOnLaunch.value = reloadScrollback
		Preferences.Logging.loadHistoryLazily.value = false
		defer {
			Preferences.Logging.reloadScrollbackOnLaunch.value = previousReload
			Preferences.Logging.loadHistoryLazily.value = previousLazy
		}
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString,
			isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let store = HistoricLogStore(filenameStore: HistoricLogFilenameFixture("removal.sqlite"))
		let historyClient = HistoricLogClient(
			store: store, databaseDirectory: { directory.path }, reportFailure: { Issue.record(Comment(rawValue: $0)) }
		)
		let history = LogControllerHistoricLogFile(client: historyClient)
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		let controller = LogController(
			client: client, in: window, inlineImageLoader: NativeInlineImageLoader(), historicLog: history
		)
		controller.historyPageFetcher = { await historyClient.fetchOutcome($0) }
		var line = LogLine()
		line.messageBody = "retained archive"
		line.lineType = .privateMessage
		let entry = line.historicEntry(forView: client.uniqueIdentifier)
		#expect(!entry.data.isEmpty)
		#expect(await historyClient.retryLoading())
		await historyClient.writeEntry(entry)
		await store.saveData()
		let view = controller.ensureBackingView()
		await controller.drainRenderJobs()
		if !reloadScrollback {
			view
				.appendLines([LogController.renderJob(LogLineRenderRequest(logLine: line, context: .init()))
						.transcriptLine])
		}
		#expect(view.displayedLines
			.map { $0.historyCursor?.lineIdentifier ?? $0.lineNumber } == [line.uniqueIdentifier])
		var completed = false
		controller.print(LogLine()) { _ in completed = true }
		let presentation: any TreeItemPresentation = controller
		presentation.tearDown(preservingLocalData ? .preservingRemoval : .permanentRemoval)
		#expect(controller.backingView == nil)
		#expect(!controller.viewIsLoaded)
		#expect(view.displayedLines.isEmpty)
		#expect((controller.historicLogMutationTask == nil) == preservingLocalData)
		await controller.historicLogMutationTask?.value
		await controller.drainRenderJobs()
		#expect(!completed)
		// Later registry/application teardown must not turn a preserving removal into deletion.
		presentation.tearDown(.applicationTermination)
		presentation.tearDown(.permanentRemoval)
		if preservingLocalData {
			#expect(controller.historicLogMutationTask == nil)
		}
		await historyClient.prepareForTermination()
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		let request = HistoricLogFetchRequest(
			viewIdentifier: client.uniqueIdentifier, kind: .newest(ascending: true, fetchLimit: 10, limitToDate: nil)
		)
		switch await store.fetchOutcome(request) {
		case let .page(entries):
			#expect(entries.map(\.uniqueIdentifier) == (preservingLocalData ? [entry.uniqueIdentifier] : []))
			#expect(entries.map(\.data) == (preservingLocalData ? [entry.data] : []))
		default: Issue.record("Could not read the isolated store after removal")
		}
		await store.close()
	}
}
