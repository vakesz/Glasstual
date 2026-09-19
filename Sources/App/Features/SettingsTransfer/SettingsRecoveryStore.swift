// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated struct SettingsRecoveryBackup: Identifiable, Equatable, Sendable {
	let url: URL
	let created: Date
	var id: URL {
		url
	}
}

/** The owner-only folder recovery files are written into.

 Every file lands whole or not at all: it is written to a hidden temporary
 file that is already private, flushed, and only then moved into place. */
nonisolated struct SettingsProtectedFolder: Sendable {
	let url: URL

	func write(_ data: Data, named name: String) throws -> URL {
		let files = FileManager.default
		try files.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		guard try files.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory else {
			throw CocoaError(.fileWriteNoPermission)
		}
		try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
		let destination = url.appendingPathComponent(name)
		let temporary = url.appendingPathComponent(".\(UUID().uuidString).tmp")
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
		try files.moveItem(at: temporary, to: destination)
		return destination
	}
}

/// Backups survive process exit. Only this directory's own archives are pruned.
actor SettingsRecoveryStore {
	let directory: URL
	nonisolated static let retentionCount = 5

	init(directory: URL) {
		self.directory = directory
	}

	/// Where this Mac keeps its configuration backups.
	@MainActor
	static var defaultDirectory: URL {
		(ApplicationPaths.applicationSupportURL ?? URL.applicationSupportDirectory)
			.appendingPathComponent("Configuration Backups", isDirectory: true)
	}

	func backups() throws -> [SettingsRecoveryBackup] {
		guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
		return try FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey],
			options: [.skipsHiddenFiles]
		).filter { $0.pathExtension == "plist" && $0.lastPathComponent.hasPrefix("Configuration-") }
			.compactMap { url in
				let values = try url.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey])
				guard values.isRegularFile == true else { return nil }
				return SettingsRecoveryBackup(url: url, created: values.creationDate ?? .distantPast)
			}
			.sorted(by: Self.newestFirst)
	}

	/// Newest first, with the filename as the tiebreaker so two backups written
	/// within the same timestamp still have one stable order.
	private nonisolated static func newestFirst( // nonisolated: pure
		_ first: SettingsRecoveryBackup, _ second: SettingsRecoveryBackup
	) -> Bool {
		guard first.created == second.created else { return first.created > second.created }
		return first.url.lastPathComponent > second.url.lastPathComponent
	}

	func save(_ archive: SettingsArchive) throws -> SettingsRecoveryBackup {
		let data = try archive.recoveryEncoded()
		// Prove the recovery document is readable before permitting any destructive work.
		_ = try SettingsArchive.decode(data, source: .localRecovery)
		let url = try SettingsProtectedFolder(url: directory)
			.write(data, named: "Configuration-\(UUID().uuidString).plist")
		for expired in try backups().filter({ $0.url != url }).dropFirst(Self.retentionCount - 1) {
			try FileManager.default.removeItem(at: expired.url)
		}
		return SettingsRecoveryBackup(url: url, created: Date())
	}

	/// A file cannot grant itself local-recovery privileges by declaring a format string.
	/// Only this store's private, regular files may restore local certificate references.
	func read(_ backup: SettingsRecoveryBackup) throws -> SettingsArchive {
		let url = backup.url.standardizedFileURL
		guard url.deletingLastPathComponent() == directory.standardizedFileURL,
		      url.lastPathComponent.hasPrefix("Configuration-"), url.pathExtension == "plist"
		else {
			throw SettingsTransferError.invalidDocument
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
		return try SettingsArchive.decode(SettingsArchive.readData(from: url), source: .localRecovery)
	}
}
