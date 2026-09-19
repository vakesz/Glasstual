// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
@testable import Glasstual
import Testing

private final nonisolated class RefusingScrollbackReadStore: NSIncrementalStore { // nonisolated: immutable
	static let storeType = "RefusingScrollbackReadStore"

	override var type: String {
		Self.storeType
	}

	override func loadMetadata() throws {
		metadata = [NSStoreUUIDKey: UUID().uuidString, NSStoreTypeKey: Self.storeType]
	}

	override func execute(_ request: NSPersistentStoreRequest, with _: NSManagedObjectContext?) throws -> Any {
		if request is NSSaveChangesRequest {
			return [Any]()
		}
		throw CocoaError(.fileReadNoPermission)
	}
}

@MainActor
@Suite("Typed scrollback fetch outcomes", .serialized)
struct ScrollbackFetchOutcomeTests {
	@Test("Core Data read errors never become successful empty pages", arguments: [false, true])
	func databaseReadOutcome(failing: Bool) async throws {
		NSPersistentStoreCoordinator.registerStoreClass(RefusingScrollbackReadStore.self,
		                                                forStoreType: RefusingScrollbackReadStore.storeType)
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		try await context.perform {
			let url = try #require(Bundle(for: Connection.self).url(
				forResource: ScrollbackQueries.modelName, withExtension: "momd"
			))
			let model = try #require(NSManagedObjectModel(contentsOf: url))
			let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
			// Custom stores need a URL; only the in-memory store supports nil here.
			let storeURL = try #require(URL(string: "scrollback-read-failure://fixture/\(UUID().uuidString)"))
			_ = try coordinator.addPersistentStore(
				ofType: failing ? RefusingScrollbackReadStore.storeType : NSInMemoryStoreType,
				configurationName: nil,
				at: failing ? storeURL : nil,
				options: nil
			)
			context.persistentStoreCoordinator = coordinator
			let result = ScrollbackQueries.fetchRowPage(
				in: context, viewIdentifier: "view", before: nil, fetchLimit: 10, limitToDate: nil
			)
			if failing {
				guard case let .failed(.read(reason)) = result else {
					Issue.record("Core Data read failure was classified as exhaustion")
					return
				}
				#expect(reason == CocoaError(.fileReadNoPermission).localizedDescription)
				let older = ScrollbackQueries.fetchOutcome(
					in: context, viewIdentifier: "view", before: "unreadable-cursor", fetchLimit: 10, limitToDate: nil
				)
				guard case let .failed(.read(olderReason)) = older else {
					Issue.record("The failed cursor lookup was classified as exhaustion")
					return
				}
				#expect(olderReason == reason)
				#expect(ScrollbackQueries.fetchRowPage(
					in: context, viewIdentifier: "view", before: nil, fetchLimit: 10, limitToDate: nil
				).entries.isEmpty)
				return
			}
			guard case let .page(entries) = result else {
				Issue.record("An empty readable store was classified as failure")
				return
			}
			#expect(entries.isEmpty)
			let entry = ScrollbackEntry(lineData: Data(), uniqueIdentifier: "anchor", viewIdentifier: "view",
			                            sessionIdentifier: 1, creationDate: 1)
			ScrollbackQueries.insert(entry, in: context, entryIdentifier: 1)
			let oldest = ScrollbackQueries.fetchOutcome(in: context, viewIdentifier: "view", before: "anchor",
			                                            fetchLimit: 10, limitToDate: nil)
			guard case let .page(older) = oldest else {
				Issue.record("The oldest valid cursor did not prove exhaustion")
				return
			}
			#expect(older.isEmpty)
			let missing = ScrollbackQueries.fetchOutcome(in: context, viewIdentifier: "view", before: "missing",
			                                             fetchLimit: 10, limitToDate: nil)
			guard case .failed(.missingCursor) = missing else {
				Issue.record("A missing cursor was classified as exhaustion")
				return
			}
			ScrollbackQueries.insert(entry, in: context, entryIdentifier: 2)
			let duplicate = ScrollbackQueries.fetchOutcome(in: context, viewIdentifier: "view", before: "anchor",
			                                               fetchLimit: 10, limitToDate: nil)
			guard case .failed(.ambiguousCursor) = duplicate else {
				Issue.record("An ambiguous cursor was classified as exhaustion")
				return
			}
			let invalid = ScrollbackEntry(lineData: Data(), uniqueIdentifier: "invalid", viewIdentifier: "view",
			                              sessionIdentifier: 1, creationDate: -1)
			ScrollbackQueries.insert(invalid, in: context, entryIdentifier: 3)
			let corrupt = ScrollbackQueries.fetchRowPage(in: context, viewIdentifier: "view", before: nil,
			                                             fetchLimit: 10, limitToDate: nil)
			guard case .failed(.invalidEntry) = corrupt else {
				Issue.record("A malformed row was silently skipped")
				return
			}
			#expect(try context
				.count(for: NSFetchRequest<NSManagedObject>(entityName: ScrollbackQueries.entityName)) == 3)
		}
	}
}
