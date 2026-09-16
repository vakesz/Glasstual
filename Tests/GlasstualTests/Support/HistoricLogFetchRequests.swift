/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CoreData
import Foundation
@testable import Glasstual

/// A test that holds a context beyond the store's lifetime closes its SQLite
/// connection before deleting the scratch directory.
nonisolated enum HistoricLogFixture { // nonisolated: value
	static func close(_ context: NSManagedObjectContext) async throws {
		try await context.perform {
			context.reset()
			guard let coordinator = context.persistentStoreCoordinator else { return }
			for store in coordinator.persistentStores {
				try coordinator.remove(store)
			}
			context.persistentStoreCoordinator = nil
		}
	}

	static func withContext<Result: Sendable>(
		at url: URL,
		operation: @escaping @Sendable (NSManagedObjectContext) throws -> Result
	) async throws -> Result {
		let context = try HistoricLogDatabase.makeStack(at: url)
		do {
			let result = try await context.perform { try operation(context) }
			try await close(context)
			return result
		} catch {
			try await close(context)
			throw error
		}
	}
}

/// The one page shape history tests read back with: everything a view holds,
/// oldest first. The store answers fetches with an outcome, and a test that is
/// checking what was written wants the rows.
extension HistoricLogFetchRequest {
	static func newestEntries(forView identifier: String, fetchLimit: UInt) -> Self {
		Self(
			viewIdentifier: identifier,
			kind: .newest(ascending: true, fetchLimit: fetchLimit, limitToDate: nil)
		)
	}
}

/// The rows a page carried. A failure and an empty page answer alike, so this
/// belongs to the tests that have already established which of the two they
/// are looking at; everything the application does reads the case.
extension HistoricLogFetchOutcome {
	nonisolated var entries: [HistoricLogEntry] { // nonisolated: pure
		if case let .page(entries) = self {
			entries
		} else {
			[]
		}
	}
}
