// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual

/// An in-memory Spotlight index that records its calls and can hold one upsert
/// open, so a test can overlap other operations with it.
actor FakeConversationIndexWriter: ConversationIndexWriting {
	enum Call: Equatable {
		case deleteAll
		case delete([String])
		case upsert([String])
	}

	struct Failure: Error {}

	private(set) var calls: [Call] = []
	private(set) var contents: Set<String> = []

	private var failingDeleteAlls = 0
	private var failingUpserts = 0
	private var holdsNextUpsert = false
	private var heldUpsert: CheckedContinuation<Void, Never>?
	private var heldUpsertWaiter: CheckedContinuation<Void, Never>?

	var deleteAllCount: Int {
		calls.filter { $0 == .deleteAll }.count
	}

	func failNextDeleteAlls(_ count: Int) {
		failingDeleteAlls = count
	}

	func failNextUpserts(_ count: Int) {
		failingUpserts = count
	}

	func holdNextUpsert() {
		holdsNextUpsert = true
	}

	/// Returns once an upsert is suspended inside the writer.
	func waitUntilUpsertIsHeld() async {
		guard heldUpsert == nil else { return }
		await withCheckedContinuation { heldUpsertWaiter = $0 }
	}

	func releaseHeldUpsert() {
		heldUpsert?.resume()
		heldUpsert = nil
	}

	func deleteAll() async throws {
		calls.append(.deleteAll)
		if failingDeleteAlls > 0 {
			failingDeleteAlls -= 1
			throw Failure()
		}
		contents = []
	}

	func delete(ids: [String]) async throws {
		calls.append(.delete(ids))
		contents.subtract(ids)
	}

	func upsert(_ entries: [ConversationIndexEntry]) async throws {
		let ids = entries.map(\.id)
		calls.append(.upsert(ids))
		if failingUpserts > 0 {
			failingUpserts -= 1
			throw Failure()
		}
		if holdsNextUpsert {
			holdsNextUpsert = false
			await withCheckedContinuation { continuation in
				heldUpsert = continuation
				heldUpsertWaiter?.resume()
				heldUpsertWaiter = nil
			}
		}
		contents.formUnion(ids)
	}
}
