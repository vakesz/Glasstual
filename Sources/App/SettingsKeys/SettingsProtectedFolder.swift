// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

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
