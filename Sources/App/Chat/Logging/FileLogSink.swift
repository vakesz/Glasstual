// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Darwin
import Foundation
import os

nonisolated struct FileLogDestination: Sendable, Equatable {
	nonisolated enum Folder: Sendable, Equatable {
		case bookmark(Data)
		case directory(URL)
	}

	let folder: Folder
	let relativePath: String
}

nonisolated enum FileLogOperation: Sendable, Equatable {
	case write(UUID, FileLogDestination, Date, String)
	case reopen(UUID, FileLogDestination?, Date)
	case close(UUID)
	case sweep(Date)
	case flush
	case shutdown
}

nonisolated struct FileLogResult: Sendable {
	var succeeded = true
	var outOfSpace = false

	static func failure(_ error: Error) -> Self {
		var result = Self(succeeded: false)
		var current: NSError? = error as NSError
		// Bound traversal even if a malformed underlying-error chain contains a cycle.
		for _ in 0 ..< 16 {
			guard let candidate = current else { break }
			if (candidate.domain == NSPOSIXErrorDomain && candidate.code == Int(ENOSPC)) ||
				(candidate.domain == NSCocoaErrorDomain && candidate.code == CocoaError.fileWriteOutOfSpace.rawValue)
			{
				result.outOfSpace = true
				break
			}
			current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
		}
		return result
	}
}

/// Owns all transcript handles, bookmark resolution and security-scope leases.
/// Only the FIFO consumer calls process; file operations do not suspend.
actor FileLogSink {
	private struct OpenFile: Sendable {
		let handle: FileHandle
		let scope: URL?
		let destination: FileLogDestination
		let day: Date
		var lastWrite: Date?
	}

	private let logger = Logger(subsystem: LogSubsystem.current, category: "FileLogSink")
	private var files: [UUID: OpenFile] = [:]

	isolated deinit {
		var result = FileLogResult()
		for identifier in Array(files.keys) {
			close(identifier, result: &result)
		}
	}

	func process(_ operation: FileLogOperation) -> FileLogResult {
		var result = FileLogResult()
		switch operation {
		case let .write(identifier, destination, date, string):
			do {
				try open(identifier, destination: destination, at: date, result: &result)
				try files[identifier]?.handle.write(contentsOf: Data((string + "\n").utf8))
				files[identifier]?.lastWrite = date
			} catch {
				record(error, result: &result)
				close(identifier, result: &result)
			}
		case let .reopen(identifier, destination, date):
			guard let destination else { close(identifier, result: &result); return result }
			do { try open(identifier, destination: destination, at: date, result: &result) } catch {
				record(error, result: &result)
			}
		case let .close(identifier):
			close(identifier, result: &result)
		case let .sweep(date):
			for identifier in Array(files.keys) {
				if let lastWrite = files[identifier]?.lastWrite, date.timeIntervalSince(lastWrite) > 1200 {
					close(identifier, result: &result)
				}
			}
		case .flush:
			for identifier in Array(files.keys) {
				do { try files[identifier]?.handle.synchronize() } catch {
					record(error, result: &result)
					close(identifier, result: &result)
				}
			}
		case .shutdown:
			for identifier in Array(files.keys) {
				close(identifier, result: &result)
			}
		}
		return result
	}

	private func open(
		_ identifier: UUID, destination: FileLogDestination, at date: Date, result: inout FileLogResult
	) throws {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = .current
		let day = calendar.startOfDay(for: date)
		if let file = files[identifier], file.destination == destination, file.day == day {
			return
		}
		close(identifier, result: &result)

		let root: URL
		var scope: URL?
		switch destination.folder {
		case let .bookmark(bookmark):
			var stale = false
			root = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
			               relativeTo: nil, bookmarkDataIsStale: &stale)
			guard root.startAccessingSecurityScopedResource() else {
				throw CocoaError(.fileWriteNoPermission)
			}
			scope = root
		case let .directory(directory):
			root = directory
		}
		do {
			let directory = root.appendingPathComponent(destination.relativePath, isDirectory: true)
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			let components = calendar.dateComponents([.year, .month, .day], from: date)
			let filename = String(format: "%04d-%02d-%02d.txt", components.year!, components.month!, components.day!)
			let url = directory.appendingPathComponent(filename)
			// O_CREAT without O_TRUNC preserves existing logs, including another logger's writes.
			let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, S_IRUSR | S_IWUSR)
			guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
			let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
			files[identifier] = OpenFile(
				handle: handle,
				scope: scope,
				destination: destination,
				day: day,
				lastWrite: nil
			)
		} catch {
			scope?.stopAccessingSecurityScopedResource()
			throw error
		}
	}

	private func close(_ identifier: UUID, result: inout FileLogResult) {
		guard let file = files.removeValue(forKey: identifier) else { return }
		do { try file.handle.synchronize() } catch { record(error, result: &result) }
		do { try file.handle.close() } catch { record(error, result: &result) }
		file.scope?.stopAccessingSecurityScopedResource()
	}

	private func record(_ error: Error, result: inout FileLogResult) {
		logger.error("Transcript file operation failed: \(error.localizedDescription, privacy: .public)")
		result.succeeded = false
		result.outOfSpace = result.outOfSpace || FileLogResult.failure(error).outOfSpace
	}
}
