// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

private actor OfflineHistoryArchive {
	let store: ScrollbackStore
	private(set) var requests: [ScrollbackFetchRequest] = []

	init(store: ScrollbackStore) {
		self.store = store
	}

	func fetch(_ request: ScrollbackFetchRequest) async -> ScrollbackFetchOutcome {
		requests.append(request)
		return await store.fetchOutcome(request)
	}
}

@MainActor
@Suite("Offline transcript history", .serialized)
struct TranscriptOfflineHistoryTests {
	@Test("Disconnected selection restores and pages saved history while respecting the restore preference",
	      arguments: [false, true], [false, true])
	func offlineSelectionAndPaging(selectChannelFirst: Bool, reloadOnLaunch: Bool) async throws {
		try await withArchive { archive in
			let previousReload = SettingsKeys.Logging.reloadScrollbackOnLaunch.value
			let previousLazy = SettingsKeys.Logging.loadHistoryLazily.value
			SettingsKeys.Logging.reloadScrollbackOnLaunch.value = reloadOnLaunch
			SettingsKeys.Logging.loadHistoryLazily.value = true
			defer {
				SettingsKeys.Logging.reloadScrollbackOnLaunch.value = previousReload
				SettingsKeys.Logging.loadHistoryLazily.value = previousLazy
			}
			let session = TestServerSession()
			session.enableCapability([.batch, .serverTime, .messageTags, .chatHistory])
			let channel = Conversation(config: ConversationConfig(name: "#offline-history"))
			channel.associatedSession = session
			session.conversationList = [channel]
			let chat = session.fixture.chatSession
			chat.sessions = [session]
			let window = MainWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			                        styleMask: .borderless, backing: .buffered, defer: false)
			window.sidebar.chatSessionSource = { chat }
			window.sidebar.filter = .all
			let serverController = window.transcriptControllers.controller(for: session)
			let channelController = window.transcriptControllers.controller(for: channel)
			let controllers = [serverController, channelController]
			defer {
				for controller in controllers {
					controller.tearDown(.preservingRemoval)
				}
			}
			let archivedIdentifiers = try await seedArchive(for: controllers, in: archive)
			for controller in controllers {
				controller.historyPageFetcher = { await archive.fetch($0) }
			}

			// Creating a transcript before it is selected must defer the local read.
			for controller in controllers {
				_ = controller.ensureBackingView()
				await controller.drainRenderJobs()
				#expect(controller.historyRecovery.isLoaded == false)
			}
			#expect(await archive.requests.isEmpty)
			let orderedItems: [ChatItem] = selectChannelFirst ? [channel, session] : [session, channel]
			for item in orderedItems {
				window.select(item)
				let controller = try #require(item.transcriptController)
				await controller.drainRenderJobs()
				let view = try #require(window.columnModel.transcript)
				let expected = try #require(archivedIdentifiers[item.uniqueIdentifier])
				#expect(window.selectedItem === item)
				#expect(view === controller.backingView)
				#expect(controller.historyRecovery.isLoaded)
				if reloadOnLaunch == false {
					#expect(view.displayedLines.isEmpty)
					#expect(await archive.requests.isEmpty)
					continue
				}
				#expect(view.displayedLines.compactMap { $0.historyCursor?.lineIdentifier } == Array(expected.suffix(100)))
				#expect(view.displayedLines.map(\.body.plainText) == (2 ..< 102).map { "Saved message \($0)" })
				#expect(view.displayedLines.allSatisfy { $0.historyCursor != nil })

				controller.loadOlderHistory()
				await controller.drainRenderJobs()
				#expect(view.displayedLines.compactMap { $0.historyCursor?.lineIdentifier } == expected)
				#expect(view.displayedLines.map(\.body.plainText) == (0 ..< 102).map { "Saved message \($0)" })
				let oldestDisplayedIdentifier = try #require(view.displayedLines.first?.lineNumber)
				controller.loadOlderHistory()
				await controller.drainRenderJobs()
				#expect(controller.locallyExhaustedBefore == oldestDisplayedIdentifier)
				#expect(controller.serverHistory.request == nil)
			}
			let requestsBeforeRevisit = await archive.requests.count
			window.select(orderedItems[0])
			let revisitedController = try #require(window.selectedViewController)
			await revisitedController.drainRenderJobs()
			#expect(await archive.requests.count == requestsBeforeRevisit)
			#expect(window.columnModel.transcript?.displayedLines.count == (reloadOnLaunch ? 102 : 0))
			#expect(session.isConnected == false)
			#expect(session.isLoggedIn == false)
			#expect(session.sentLines.count == 0)
			#expect(session.socket == nil)
		}
	}

	private func seedArchive(
		for controllers: [TranscriptController],
		in archive: OfflineHistoryArchive
	) async throws -> [String: [String]] {
		var archivedIdentifiers: [String: [String]] = [:]
		for controller in controllers {
			var identifiers: [String] = []
			for index in 0 ..< 102 {
				var line = ChatLine()
				line.messageBody = "Saved message \(index)"
				line.nickname = "alice"
				line.lineType = .privateMessage
				line.receivedAt = Date(timeIntervalSince1970: TimeInterval(1000 + index))
				identifiers.append(line.uniqueIdentifier)
				let entry = line.scrollbackEntry(forView: controller.uniqueIdentifier)
				try #require(await archive.store.writeChatLine(entry) == .accepted)
			}
			archivedIdentifiers[controller.uniqueIdentifier] = identifiers
		}
		try #require(await archive.store.close() == .saved)
		try #require(await archive.store.openDatabase(inDirectory: archiveDirectory).isOpen)
		await archive.store.setMaximumLineCount(1000)
		return archivedIdentifiers
	}

	private var archiveDirectory: String {
		FileManager.default.temporaryDirectory.appendingPathComponent("offline-history-\(identifier)").path
	}

	private let identifier = UUID().uuidString

	private func withArchive(_ body: (OfflineHistoryArchive) async throws -> Void) async throws {
		let directory = archiveDirectory
		try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture().store,
		                            resizeDelay: { .seconds(3600) })
		try #require(await store.openDatabase(inDirectory: directory).isOpen)
		await store.setMaximumLineCount(1000)
		do {
			try await body(OfflineHistoryArchive(store: store))
		} catch {
			_ = await store.close()
			throw error
		}
		#expect(await store.close() == .saved)
	}
}
