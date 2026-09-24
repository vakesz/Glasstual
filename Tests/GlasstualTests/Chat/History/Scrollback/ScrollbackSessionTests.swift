// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
import Foundation
@testable import Glasstual
import Synchronization
import Testing

private actor ScrollbackOperationGate {
	private var entered = false
	private var observer: CheckedContinuation<Void, Never>?
	private var blocked: CheckedContinuation<Void, Never>?
	private var released = false

	func wait() async {
		guard !released else { return }
		entered = true
		observer?.resume()
		observer = nil
		await withCheckedContinuation { blocked = $0 }
	}

	func ready() async {
		guard !entered else { return }
		await withCheckedContinuation { observer = $0 }
	}

	func release() {
		released = true
		blocked?.resume()
		blocked = nil
	}
}

private actor ScrollbackOperationRecorder {
	private(set) var operations: [ScrollbackStoreOperation] = []

	func record(_ operation: ScrollbackStoreOperation) {
		operations.append(operation)
	}
}

private actor ScrollbackDirectory {
	var path: String?

	init(_ path: String?) {
		self.path = path
	}

	func set(_ path: String?) {
		self.path = path
	}
}

@MainActor
@Suite("Scrollback session", .serialized)
struct ScrollbackSessionTests {
	private func directory() throws -> URL {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	private func entry(_ identifier: String) -> ScrollbackEntry {
		ScrollbackEntry(
			lineData: Data(identifier.utf8),
			uniqueIdentifier: identifier,
			viewIdentifier: "view",
			sessionIdentifier: 1,
			creationDate: TimeInterval(identifier.count)
		)
	}

	private func newest() -> ScrollbackFetchRequest {
		.newestEntries(forView: "view", fetchLimit: 10)
	}

	private func storage(
		in directory: URL,
		willPerform: (@Sendable (ScrollbackStoreOperation) async -> Void)? = nil
	) throws -> (store: ScrollbackStore, context: NSManagedObjectContext) {
		let context = try ScrollbackQueries.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture().store,
		                            makeStack: { _ in context }, willPerform: willPerform)
		return (store, context)
	}

	private func session(
		store: ScrollbackStore,
		directory: @escaping @Sendable () async -> String?,
		reportFailure: @escaping @MainActor @Sendable (String) -> Void = { Issue.record(Comment(rawValue: $0)) }
	) -> ScrollbackSession {
		ScrollbackSession(store: store, databaseDirectory: directory, reportFailure: reportFailure)
	}

	@Test("An empty page and an unavailable database remain different outcomes")
	func emptyPageIsNotFailure() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let (store, context) = try storage(in: directory)
		let session = session(store: store, directory: { directory.path })
		switch await session.fetchOutcome(newest()) {
		case let .page(entries): #expect(entries.isEmpty)
		default: Issue.record("An empty store did not return a successful page")
		}
		#expect(await session.isLoaded)
		#expect(await session.prepareForTermination() == .saved)
		switch await store.fetchOutcome(newest()) {
		case .failed(.unavailable): break
		default: Issue.record("A closed store did not report unavailability")
		}
		try await ScrollbackFixture.close(context)
	}

	@Test("A malformed page remains a failure and a later valid page can load")
	func invalidPageCanBeRetried() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let (store, context) = try storage(in: directory)
		let session = session(store: store, directory: { directory.path })
		let invalid = ScrollbackEntry(
			lineData: Data(), uniqueIdentifier: "invalid", viewIdentifier: "view",
			sessionIdentifier: 1, creationDate: -1
		)
		#expect(await session.writeEntry(invalid) == .accepted)
		if case .failed(.invalidEntry) = await session.fetchOutcome(newest()) {} else {
			Issue.record("A malformed row was reported as an empty page")
		}
		if case .deleted = await session.removeHistory("view", forget: false) {} else {
			Issue.record("The malformed row could not be cleared")
		}
		#expect(await session.writeEntry(entry("valid")) == .accepted)
		#expect(await session.fetchOutcome(newest()).entries.map(\.uniqueIdentifier) == ["valid"])
		#expect(await session.prepareForTermination() == .saved)
		try await ScrollbackFixture.close(context)
	}

	@Test("Cancelling a page held at transaction admission reports cancellation")
	func cancelledFetchHasTypedOutcome() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let gate = ScrollbackOperationGate()
		let (store, context) = try storage(in: directory, willPerform: { operation in
			if case .fetch = operation {
				await gate.wait()
			}
		})
		let session = session(store: store, directory: { directory.path })
		#expect(await session.retryLoading())
		let request = newest()
		let task = Task { await session.fetchOutcome(request) }
		await gate.ready()
		task.cancel()
		await gate.release()
		if case .cancelled = await task.value {} else {
			Issue.record("Cancellation was reported as a page")
		}
		#expect(await session.prepareForTermination() == .saved)
		try await ScrollbackFixture.close(context)
	}

	@Test("Synchronous writes, a clear, and a later page use one request order")
	func changesRunInTheOrderTheyWereAskedFor() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let recorder = ScrollbackOperationRecorder()
		let (store, context) = try storage(in: directory, willPerform: { operation in
			await recorder.record(operation)
		})
		let session = session(store: store, directory: { directory.path })
		#expect(await session.retryLoading())
		session.write(entry("first")) { #expect($0 == .accepted) }
		session.write(entry("second")) { #expect($0 == .accepted) }
		let queued = session.removeHistory(forView: "view", forget: false) { outcome in
			guard case let .deleted(result) = outcome else {
				Issue.record("The clear did not run")
				return
			}
			#expect(result.uniqueIdentifiers == ["first", "second"])
		}
		#expect(queued)
		session.write(entry("third")) { #expect($0 == .accepted) }
		let page = await session.fetchOutcome(newest())
		#expect(page.entries.map(\.uniqueIdentifier) == ["third"])
		#expect(await recorder.operations == [.write, .write, .reset, .write, .fetch])
		#expect(await session.prepareForTermination() == .saved)
		try await ScrollbackFixture.close(context)
	}

	@Test("An open failure stays latched until explicit retry")
	func failedOpenRequiresExplicitRetry() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let attempts = Mutex<Int>(0)
		let shouldFail = Mutex<Bool>(true)
		let context = try ScrollbackQueries.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture().store, makeStack: { url in
			attempts.withLock { $0 += 1 }
			if shouldFail.withLock({ $0 }) {
				throw NSError(domain: "Injected open failure", code: 1)
			}
			#expect(url == directory.appendingPathComponent("history.sqlite"))
			return context
		})
		var reports: [String] = []
		let session = session(store: store, directory: { directory.path }, reportFailure: { reports.append($0) })
		#expect(await session.writeEntry(entry("first")) == .unavailable)
		#expect(await session.isUnavailable)
		#expect(attempts.withLock { $0 } == 1)
		let blocked = entry("blocked")
		let request = newest()
		await withTaskGroup(of: Void.self) { group in
			for _ in 0 ..< 10 {
				group.addTask { _ = await session.writeEntry(blocked) }
				group.addTask { _ = await session.fetchOutcome(request) }
			}
		}
		#expect(attempts.withLock { $0 } == 1)
		#expect(reports.count == 1)
		#expect(await session.retryLoading() == false)
		#expect(attempts.withLock { $0 } == 2)
		#expect(reports.count == 2)
		shouldFail.withLock { $0 = false }
		#expect(await session.writeEntry(entry("still blocked")) == .unavailable)
		#expect(attempts.withLock { $0 } == 2)
		#expect(await session.retryLoading())
		#expect(attempts.withLock { $0 } == 3)
		#expect(await session.writeEntry(entry("accepted")) == .accepted)
		#expect(await session.fetchOutcome(newest()).entries.map(\.uniqueIdentifier) == ["accepted"])
		#expect(await session.prepareForTermination() == .saved)
		#expect(await session.retryLoading() == false)
		#expect(attempts.withLock { $0 } == 3)
		try await ScrollbackFixture.close(context)
	}

	@Test("A missing setup directory remains retryable without an open failure")
	func missingDatabaseDirectoryAnswersSafely() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let path = ScrollbackDirectory(nil)
		let (store, context) = try storage(in: directory)
		let session = session(store: store, directory: { await path.path }, reportFailure: {
			Issue.record("No database open failed: \($0)")
		})
		switch await session.fetchOutcome(newest()) {
		case .failed(.unavailable): break
		default: Issue.record("A missing directory was not reported as unavailable")
		}
		#expect(await session.isLoaded == false)
		#expect(await session.isUnavailable == false)
		await path.set(directory.path)
		#expect(await session.fetchOutcome(newest()).entries.isEmpty)
		#expect(await session.isLoaded)
		#expect(await session.prepareForTermination() == .saved)
		try await ScrollbackFixture.close(context)
	}
}
