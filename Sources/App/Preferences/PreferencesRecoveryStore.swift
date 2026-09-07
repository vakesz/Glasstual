/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

nonisolated struct PreferencesRecoveryBackup: Identifiable, Equatable, Sendable { // nonisolated: value
	let url: URL
	let created: Date
	var id: URL {
		url
	}
}

/// Backups survive process exit. Only this directory's own archives are pruned.
actor PreferencesRecoveryStore {
	let directory: URL
	nonisolated static let retentionCount = 5 // nonisolated: let

	init(directory: URL) {
		self.directory = directory
	}

	func backups() throws -> [PreferencesRecoveryBackup] {
		guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
		return try FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey],
			options: [.skipsHiddenFiles]
		).filter { $0.pathExtension == "plist" && $0.lastPathComponent.hasPrefix("Configuration-") }
			.compactMap { url in
				let values = try url.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey])
				guard values.isRegularFile == true else { return nil }
				return PreferencesRecoveryBackup(url: url, created: values.creationDate ?? .distantPast)
			}
			.sorted(by: Self.newestFirst)
	}

	/// Newest first, with the filename as the tiebreaker so two backups written
	/// within the same timestamp still have one stable order.
	private nonisolated static func newestFirst( // nonisolated: pure
		_ first: PreferencesRecoveryBackup, _ second: PreferencesRecoveryBackup
	) -> Bool {
		guard first.created == second.created else { return first.created > second.created }
		return first.url.lastPathComponent > second.url.lastPathComponent
	}

	func save(_ archive: PreferencesArchive) throws -> PreferencesRecoveryBackup {
		let data = try archive.recoveryEncoded()
		// Prove the recovery document is readable before permitting any destructive work.
		_ = try PreferencesArchive.decode(data, source: .localRecovery)
		let files = FileManager.default
		try files.createDirectory(
			at: directory,
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700]
		)
		guard try files.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
			throw CocoaError(.fileWriteNoPermission)
		}
		try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
		let url = directory.appendingPathComponent("Configuration-\(UUID().uuidString).plist")
		let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
		guard files.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
			throw CocoaError(.fileWriteUnknown)
		}
		defer { try? files.removeItem(at: temporary) }
		try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
		let handle = try FileHandle(forWritingTo: temporary)
		do {
			try handle.write(contentsOf: data)
			try handle.synchronize()
			try handle.close()
		} catch {
			try? handle.close()
			throw error
		}
		try files.moveItem(at: temporary, to: url)
		for expired in try backups().filter({ $0.url != url }).dropFirst(Self.retentionCount - 1) {
			try FileManager.default.removeItem(at: expired.url)
		}
		return PreferencesRecoveryBackup(url: url, created: Date())
	}

	/// A file cannot grant itself local-recovery privileges by declaring a format string.
	/// Only this store's private, regular files may restore local certificate references.
	func read(_ backup: PreferencesRecoveryBackup) throws -> PreferencesArchive {
		let url = backup.url.standardizedFileURL
		guard url.deletingLastPathComponent() == directory.standardizedFileURL,
		      url.lastPathComponent.hasPrefix("Configuration-"), url.pathExtension == "plist"
		else {
			throw PreferencesTransferError.invalidDocument
		}
		let files = FileManager.default
		let folderAttributes = try files.attributesOfItem(atPath: directory.path)
		let attributes = try files.attributesOfItem(atPath: url.path)
		guard folderAttributes[.type] as? FileAttributeType == .typeDirectory,
		      (folderAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
		      attributes[.type] as? FileAttributeType == .typeRegular,
		      (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600
		else {
			throw CocoaError(.fileReadNoPermission)
		}
		return try PreferencesArchive.decode(PreferencesArchive.readData(from: url), source: .localRecovery)
	}
}
