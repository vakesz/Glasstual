/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Darwin
import Foundation
import os

nonisolated struct FileLogDestination: Sendable, Equatable { // nonisolated: value
	nonisolated enum Folder: Sendable, Equatable { // nonisolated: value
		case bookmark(Data)
		case directory(URL)
	}

	let folder: Folder
	let relativePath: String
}

nonisolated enum FileLogOperation: Sendable, Equatable { // nonisolated: value
	case write(UUID, FileLogDestination, Date, String)
	case reopen(UUID, FileLogDestination?, Date)
	case close(UUID)
	case sweep(Date)
	case flush
	case shutdown
}

nonisolated struct FileLogResult: Sendable { // nonisolated: value
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

protocol FileLogSinking: Actor {
	func process(_ operation: FileLogOperation) async -> FileLogResult
}

/// One consumer, not one Task per write. Awaiting even a reentrant test sink
/// cannot let the next command overtake the current one.
@MainActor
final class FileLogCommands {
	private struct Command: Sendable {
		let operation: FileLogOperation
		var completion: (@MainActor @Sendable (Bool) -> Void)?
	}

	private let continuation: AsyncStream<Command>.Continuation
	private var idleSweepTask: Task<Void, Never>?
	private var finished = false

	init(
		sink: any FileLogSinking = FileLogSink(),
		reportNoSpace: @escaping @MainActor @Sendable () -> Void = { FileLogger.reportNoSpace() }
	) {
		let (stream, continuation) = AsyncStream<Command>.makeStream()
		self.continuation = continuation
		Task {
			var succeeded = true
			for await command in stream {
				let result = await sink.process(command.operation)
				succeeded = succeeded && result.succeeded
				if result.outOfSpace {
					reportNoSpace()
				}
				command.completion?(succeeded)
				if case .shutdown = command.operation {
					return
				}
			}
			_ = await sink.process(.shutdown)
		}
		idleSweepTask = Task { [weak self] in
			while !Task.isCancelled {
				do { try await Task.sleep(for: .seconds(600)) } catch { return }
				self?.submit(.sweep(Date()))
			}
		}
	}

	isolated deinit {
		idleSweepTask?.cancel()
		continuation.finish()
	}

	@discardableResult
	func submit(_ operation: FileLogOperation) -> Bool {
		guard !finished else { return false }
		if case .shutdown = operation {
			return false
		}
		continuation.yield(Command(operation: operation))
		return true
	}

	/// Reports all failures since this stream was created, not merely fsync errors.
	func flush() async -> Bool {
		guard !finished else { return false }
		return await withCheckedContinuation { barrier in
			continuation.yield(Command(operation: .flush, completion: { barrier.resume(returning: $0) }))
		}
	}

	func finish(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
		guard !finished else { completion(false); return }
		finished = true
		idleSweepTask?.cancel()
		idleSweepTask = nil
		continuation.yield(Command(operation: .shutdown, completion: completion))
		continuation.finish()
	}
}

/// Owns all transcript handles, bookmark resolution and security-scope leases.
/// Only the FIFO consumer calls process; file operations do not suspend.
actor FileLogSink: FileLogSinking {
	private struct OpenFile: Sendable {
		let handle: FileHandle
		let scope: URL?
		let destination: FileLogDestination
		let day: Date
		var lastWrite: Date?
	}

	private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Glasstual", category: "FileLogger")
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
