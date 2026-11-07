// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
import Foundation

/// Locates the compiled scrollback model in the app bundle rather than the
/// current process bundle, which is different in tests and helper processes.
private final nonisolated class ScrollbackModelBundleToken {} // nonisolated: immutable

/** The three schemas a scrollback store has had, and the one this build writes.

 - Unindexed: the shipped entity, with no indexes.
 - Indexed: the same entity with the query indexes. Core Data excludes indexes
 from an entity's version hash, so a version modifier tells the two apart.
 - Searchable: the indexed entity with the plain-text columns a search reads
 (``ScrollbackSearchFields``), which is the schema this build opens.

 A group of values rather than a tuple, because the migration names each of
 them. */
nonisolated struct ScrollbackModelVersions {
	let unindexed: NSManagedObjectModel
	let indexed: NSManagedObjectModel
	let searchable: NSManagedObjectModel

	/// The schemas older than the current one, newest first: the order an
	/// existing store is matched against.
	var olderThanCurrent: [NSManagedObjectModel] {
		[indexed, unindexed]
	}
}

/** Brings an existing history store up to the schema this build writes, once,
 under the rules automatic migration would break: it is disabled for this
 store, so nothing infers a mapping and nothing changes the file in place.

 The upgrade copies every row into a new store beside the old one, filling the
 searchable columns from each row's archive as it goes, checks the row count,
 and only then replaces the old store with the copy. Until that last step the
 old store is untouched, so a failure or a crash at any point leaves history
 exactly as it was, and the next launch discards the half-built copy and starts
 again. A row whose archive cannot be read is copied with empty search columns:
 it stays in history and is not searchable, and it never fails the upgrade. */
nonisolated enum ScrollbackModelMigration {
	private static let indexedVersion = "GlasstualScrollbackIndexesV1"
	private static let searchableVersion = "GlasstualScrollbackSearchV2"
	/// How many rows are copied, and saved, together: the most a migration
	/// holds in memory at a time.
	static let copyBatchSize = 500

	static func loadUnindexedModel() throws -> NSManagedObjectModel {
		guard let modelURL = Bundle(for: ScrollbackModelBundleToken.self)
			.url(forResource: ScrollbackQueries.modelName, withExtension: "momd"),
			let model = NSManagedObjectModel(contentsOf: modelURL)
		else { throw CocoaError(.fileNoSuchFile) }
		return model
	}

	static func indexedModel(from unindexedModel: NSManagedObjectModel) throws -> NSManagedObjectModel {
		guard let model = unindexedModel.copy() as? NSManagedObjectModel,
		      let entity = model.entitiesByName[ScrollbackQueries.entityName]
		else { throw CocoaError(.persistentStoreInvalidType) }

		func index(_ name: String, _ attributes: [ScrollbackAttribute]) throws -> NSFetchIndexDescription {
			let elements = try attributes.map { attribute in
				guard let property = entity.propertiesByName[attribute.rawValue] else {
					throw CocoaError(.persistentStoreInvalidType)
				}
				return NSFetchIndexElementDescription(property: property, collationType: .binary)
			}
			return NSFetchIndexDescription(name: name, elements: elements)
		}

		entity.indexes = try [
			index("byViewAndDate", [.viewID, .createdAt, .entryID, .lineID]),
			index("byViewAndLine", [.viewID, .lineID]),
			index("byViewAndEntry", [.viewID, .entryID]),
		]
		entity.versionHashModifier = indexedVersion
		return model
	}

	/// The indexed schema plus the plain-text columns a search reads.
	static func searchableModel(from indexedModel: NSManagedObjectModel) throws -> NSManagedObjectModel {
		guard let model = indexedModel.copy() as? NSManagedObjectModel,
		      let entity = model.entitiesByName[ScrollbackQueries.entityName]
		else { throw CocoaError(.persistentStoreInvalidType) }

		let columns = [ScrollbackAttribute.plainText, .sender, .searchText].map { attribute in
			let description = NSAttributeDescription()
			description.name = attribute.rawValue
			description.attributeType = .stringAttributeType
			description.isOptional = true
			return description
		}
		entity.properties += columns
		entity.versionHashModifier = searchableVersion
		return model
	}

	static func versions() throws -> ScrollbackModelVersions {
		let unindexed = try loadUnindexedModel()
		let indexed = try indexedModel(from: unindexed)
		return try ScrollbackModelVersions(
			unindexed: unindexed, indexed: indexed, searchable: searchableModel(from: indexed)
		)
	}

	/// The working copy an upgrade builds beside the store. The name is the one
	/// the index-only upgrade used, so a copy an earlier build left is found and
	/// dealt with by the same rule.
	static func workingCopyURL(for url: URL) -> URL {
		url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).indexing.sqlite")
	}

	/// - Parameter progress: Told the fraction of rows copied, from 0 to 1, as
	///   the copy advances. Never called when there is nothing to upgrade.
	static func upgradeIfNeeded(
		at url: URL,
		versions: ScrollbackModelVersions,
		using coordinator: NSPersistentStoreCoordinator,
		options: [AnyHashable: Any],
		progress: (@Sendable (Double) -> Void)? = nil
	) throws {
		guard FileManager.default.fileExists(atPath: url.path) else { return }
		let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
			type: .sqlite, at: url, options: options
		)
		let temporaryURL = workingCopyURL(for: url)
		if versions.searchable.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
			// A previous process may have stopped after replacement but before
			// removing its working copy. Keep that copy if row counts disagree.
			if FileManager.default.fileExists(atPath: temporaryURL.path),
			   let storedCount = try? rowCount(at: url, model: versions.searchable, options: options)
			{
				let temporaryCount = try? rowCount(at: temporaryURL, model: versions.searchable, options: options)
				if temporaryCount == nil || temporaryCount == storedCount {
					_ = discardTemporary(at: temporaryURL, using: coordinator, options: options)
				}
			}
			return
		}
		// Unknown schemas remain untouched. The normal open will report its
		// incompatibility, as it did before the schema had searchable columns.
		guard let source = versions.olderThanCurrent.first(where: {
			$0.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
		}) else { return }

		// The source is still intact, so any copy interrupted before replacement
		// is safe to discard and rebuild.
		guard discardTemporary(at: temporaryURL, using: coordinator, options: options) else {
			throw CocoaError(.fileWriteUnknown)
		}
		var preserveTemporaryCopy = false
		defer {
			if !preserveTemporaryCopy {
				_ = discardTemporary(at: temporaryURL, using: coordinator, options: options)
			}
		}

		let sourceCount = try rowCount(at: url, model: source, options: options)
		progress?(0)
		try copyRows(
			from: url, sourceModel: source, to: temporaryURL, destinationModel: versions.searchable,
			options: options, expectedCount: sourceCount, progress: progress
		)
		guard try rowCount(at: temporaryURL, model: versions.searchable, options: options) == sourceCount else {
			throw CocoaError(.persistentStoreIncompleteSave)
		}
		// If replacement or the destination read fails, retain the checked
		// temporary copy as a recovery source.
		preserveTemporaryCopy = true
		try coordinator.replacePersistentStore(
			at: url, destinationOptions: options,
			withPersistentStoreFrom: temporaryURL, sourceOptions: options, type: .sqlite
		)
		guard try rowCount(at: url, model: versions.searchable, options: options) == sourceCount else {
			throw CocoaError(.persistentStoreIncompleteSave)
		}
		preserveTemporaryCopy = false
		progress?(1)
	}

	/** Copies every row of the old store into a new one, in batches.

	 Each row keeps all six original columns exactly; the searchable columns are
	 derived from its archive. The batches bound memory: a batch is saved and
	 forgotten before the next is read. */
	private static func copyRows(
		from sourceURL: URL,
		sourceModel: NSManagedObjectModel,
		to destinationURL: URL,
		destinationModel: NSManagedObjectModel,
		options: [AnyHashable: Any],
		expectedCount: Int,
		progress: (@Sendable (Double) -> Void)?
	) throws {
		let sourceCoordinator = NSPersistentStoreCoordinator(managedObjectModel: sourceModel)
		let sourceStore = try sourceCoordinator.addPersistentStore(type: .sqlite, at: sourceURL, options: options)
		defer { try? sourceCoordinator.remove(sourceStore) }
		let destinationCoordinator = NSPersistentStoreCoordinator(managedObjectModel: destinationModel)
		let destinationStore = try destinationCoordinator.addPersistentStore(
			type: .sqlite, at: destinationURL, options: options
		)
		defer { try? destinationCoordinator.remove(destinationStore) }

		let source = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		source.persistentStoreCoordinator = sourceCoordinator
		let destination = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		destination.persistentStoreCoordinator = destinationCoordinator

		/* Identifiers only, so what is held for the whole copy is a few dozen
		 bytes a row; the rows themselves are read one batch at a time. */
		let identifiers = try source.performAndWait {
			let request = NSFetchRequest<NSManagedObjectID>(entityName: ScrollbackQueries.entityName)
			request.resultType = .managedObjectIDResultType
			return try source.fetch(request)
		}
		var copied = 0
		while copied < identifiers.count {
			let start = copied
			let end = min(copied + copyBatchSize, identifiers.count)
			let batchIdentifiers = Array(identifiers[start ..< end])
			let batch = try source.performAndWait {
				let request = NSFetchRequest<NSManagedObject>(entityName: ScrollbackQueries.entityName)
				request.predicate = NSPredicate(format: "SELF IN %@", batchIdentifiers)
				request.returnsObjectsAsFaults = false
				let rows = try Dictionary(
					source.fetch(request).map { ($0.objectID, $0) }, uniquingKeysWith: { first, _ in first }
				)
				let batch = batchIdentifiers.compactMap { rows[$0] }.map(CopiedRow.init)
				source.reset()
				return batch
			}
			guard batch.count == batchIdentifiers.count else { throw CocoaError(.persistentStoreIncompleteSave) }
			try destination.performAndWait {
				guard let entity = NSEntityDescription.entity(
					forEntityName: ScrollbackQueries.entityName, in: destination
				) else { throw CocoaError(.persistentStoreInvalidType) }
				for row in batch {
					row.insert(into: NSManagedObject(entity: entity, insertInto: destination))
				}
				try destination.save()
				destination.reset()
			}
			copied = end
			progress?(expectedCount > 0 ? Double(copied) / Double(expectedCount) : 1)
		}
	}

	/// What one old row carries across: its original columns exactly, and the
	/// search columns its archive yields.
	private struct CopiedRow: Sendable {
		let createdAt: NSNumber?
		let entryID: NSNumber?
		let lineData: Data?
		let lineID: String?
		let sessionID: NSNumber?
		let viewID: String?
		let search: ScrollbackSearchFields

		init(_ row: NSManagedObject) {
			createdAt = row.value(forKey: ScrollbackAttribute.createdAt.rawValue) as? NSNumber
			entryID = row.value(forKey: ScrollbackAttribute.entryID.rawValue) as? NSNumber
			lineData = row.value(forKey: ScrollbackAttribute.lineData.rawValue) as? Data
			lineID = row.value(forKey: ScrollbackAttribute.lineID.rawValue) as? String
			sessionID = row.value(forKey: ScrollbackAttribute.sessionID.rawValue) as? NSNumber
			viewID = row.value(forKey: ScrollbackAttribute.viewID.rawValue) as? String
			search = ScrollbackModelMigration.searchFields(of: row)
		}

		func insert(into object: NSManagedObject) {
			object.setValue(createdAt, forKey: ScrollbackAttribute.createdAt.rawValue)
			object.setValue(entryID, forKey: ScrollbackAttribute.entryID.rawValue)
			object.setValue(lineData, forKey: ScrollbackAttribute.lineData.rawValue)
			object.setValue(lineID, forKey: ScrollbackAttribute.lineID.rawValue)
			object.setValue(sessionID, forKey: ScrollbackAttribute.sessionID.rawValue)
			object.setValue(viewID, forKey: ScrollbackAttribute.viewID.rawValue)
			search.write(to: object)
		}
	}

	/// The searchable columns of one stored row, derived from its archive. A row
	/// that cannot be read has none: it stays in history and out of search.
	static func searchFields(of row: NSManagedObject) -> ScrollbackSearchFields {
		guard let data = row.value(forKey: ScrollbackAttribute.lineData.rawValue) as? Data,
		      let line = ChatLine(data: data)
		else { return .empty }
		return ScrollbackSearchFields(line: line)
	}

	/// Core Data handles SQLite locks and its sidecars. Remove residual empty
	/// files only after it confirms destruction; a failed destroy may mean
	/// another opener still has the working store in use.
	@discardableResult
	private static func discardTemporary(
		at url: URL, using coordinator: NSPersistentStoreCoordinator, options: [AnyHashable: Any]
	) -> Bool {
		if FileManager.default.fileExists(atPath: url.path) {
			do {
				try coordinator.destroyPersistentStore(at: url, type: .sqlite, options: options)
			} catch {
				return false
			}
		}
		for suffix in ["", "-wal", "-shm"] {
			let file = URL(fileURLWithPath: url.path + suffix)
			if FileManager.default.fileExists(atPath: file.path) {
				do {
					try FileManager.default.removeItem(at: file)
				} catch {
					return false
				}
			}
		}
		return true
	}

	private static func rowCount(
		at url: URL, model: NSManagedObjectModel, options: [AnyHashable: Any]
	) throws -> Int {
		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
		let store = try coordinator.addPersistentStore(type: .sqlite, at: url, options: options)
		defer { try? coordinator.remove(store) }
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		context.persistentStoreCoordinator = coordinator
		return try context.performAndWait {
			try context.count(for: NSFetchRequest<NSManagedObject>(entityName: ScrollbackQueries.entityName))
		}
	}
}
