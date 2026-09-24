// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
import Foundation

/// Locates the compiled scrollback model in the app bundle rather than the
/// current process bundle, which is different in tests and helper processes.
private final nonisolated class ScrollbackModelBundleToken {} // nonisolated: immutable

/// Adds query indexes to the current scrollback schema without adopting a
/// different archive format. Core Data excludes indexes from an entity's
/// version hash, so the explicit modifier makes a one-time, checked migration
/// necessary for stores that already existed before the indexes were added.
nonisolated enum ScrollbackModelMigration {
	private static let indexedVersion = "GlasstualScrollbackIndexesV1"

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

	static func upgradeIfNeeded(
		at url: URL,
		from unindexedModel: NSManagedObjectModel,
		to indexedModel: NSManagedObjectModel,
		using coordinator: NSPersistentStoreCoordinator,
		options: [AnyHashable: Any]
	) throws {
		guard FileManager.default.fileExists(atPath: url.path) else { return }
		let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
			type: .sqlite, at: url, options: options
		)
		let temporaryURL = url.deletingLastPathComponent()
			.appendingPathComponent(".\(url.lastPathComponent).indexing.sqlite")
		if indexedModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
			// A previous process may have stopped after replacement but before
			// removing its working copy. Keep that copy if row counts disagree.
			if FileManager.default.fileExists(atPath: temporaryURL.path),
			   let storedCount = try? rowCount(at: url, model: indexedModel, options: options)
			{
				let temporaryCount = try? rowCount(at: temporaryURL, model: indexedModel, options: options)
				if temporaryCount == nil || temporaryCount == storedCount {
					_ = discardTemporary(at: temporaryURL, using: coordinator, options: options)
				}
			}
			return
		}
		// Unknown schemas remain untouched. The normal open will report its
		// incompatibility, as it did before this index upgrade.
		guard unindexedModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else {
			return
		}

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

		let sourceCount = try rowCount(at: url, model: unindexedModel, options: options)
		let mapping = try NSMappingModel.inferredMappingModel(
			forSourceModel: unindexedModel, destinationModel: indexedModel
		)
		let manager = NSMigrationManager(sourceModel: unindexedModel, destinationModel: indexedModel)
		try manager.migrateStore(
			from: url, type: .sqlite, options: options, mapping: mapping,
			to: temporaryURL, type: .sqlite, options: options
		)
		guard try rowCount(at: temporaryURL, model: indexedModel, options: options) == sourceCount else {
			throw CocoaError(.persistentStoreIncompleteSave)
		}
		// If replacement or the destination read fails, retain the checked
		// temporary copy as a recovery source.
		preserveTemporaryCopy = true
		try coordinator.replacePersistentStore(
			at: url, destinationOptions: options,
			withPersistentStoreFrom: temporaryURL, sourceOptions: options, type: .sqlite
		)
		guard try rowCount(at: url, model: indexedModel, options: options) == sourceCount else {
			throw CocoaError(.persistentStoreIncompleteSave)
		}
		preserveTemporaryCopy = false
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
