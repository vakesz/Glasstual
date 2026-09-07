/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Darwin
import Foundation

/// Each recipient owns an independent scope count, including across retries.
final nonisolated class FileTransferAccessLease: Sendable { // nonisolated: immutable
	let url: URL
	let isAccessing: Bool
	private let stopAccess: @Sendable (URL) -> Void

	init(
		url: URL,
		startAccess: @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
		stopAccess: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
	) {
		self.url = url
		self.stopAccess = stopAccess
		isAccessing = startAccess(url)
	}

	deinit {
		if isAccessing {
			stopAccess(url)
		}
	}
}

/// The descriptor, not its display path, is the authority for transfer I/O.
public actor DCCTransferFile {
	public nonisolated let path: String // nonisolated: let
	public nonisolated let initialSize: UInt64 // nonisolated: let
	nonisolated let accessURL: URL // nonisolated: let
	private let handle: FileHandle
	private let device: dev_t
	private let inode: ino_t
	private let writable: Bool
	private var accessLease: FileTransferAccessLease?
	private var closed = false

	init(
		url: URL,
		receiving: Bool,
		accessURL: URL? = nil,
		startAccess: @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
		stopAccess: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
	) throws {
		let lease = FileTransferAccessLease(url: accessURL ?? url, startAccess: startAccess, stopAccess: stopAccess)
		let reservation = try Self.reserve(url: url, receiving: receiving)

		self.accessURL = lease.url
		handle = FileHandle(fileDescriptor: reservation.descriptor, closeOnDealloc: true)
		path = reservation.path
		initialSize = reservation.size
		device = reservation.device
		inode = reservation.inode
		writable = receiving
		accessLease = lease
	}

	/// The descriptor a transfer owns, and what it was opened on.
	private struct Reservation {
		let descriptor: Int32
		let path: String
		let size: UInt64
		let device: dev_t
		let inode: ino_t
	}

	/// Opens the file this transfer owns, once and exclusively.
	///
	/// A receiver never writes over a file that is already there: `O_EXCL`
	/// refuses the name and the reservation takes the next free `name_N`
	/// instead, trimming the stem so the result still fits a filename.
	private static func reserve(url: URL, receiving: Bool) throws -> Reservation {
		let directory = url.deletingLastPathComponent()
		let ext = url.pathExtension.utf8.count <= 240 ? url.pathExtension : ""
		var stem = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
		var candidate = url
		var suffix = 0
		var descriptor: Int32

		repeat {
			descriptor = Darwin.open(candidate.path, receiving
				? O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC
				: O_RDONLY | O_NONBLOCK | O_CLOEXEC, S_IRUSR | S_IWUSR)
			if descriptor >= 0 {
				break
			}
			guard receiving, errno == EEXIST else {
				throw receiving ? DCCTransferError.fileUnwritable : .fileUnreadable
			}
			suffix += 1
			let ending = ext.isEmpty ? "_\(suffix)" : "_\(suffix).\(ext)"
			while stem.utf8.count + ending.utf8.count > 255, !stem.isEmpty {
				stem.removeLast()
			}
			candidate = directory.appendingPathComponent(stem + ending)
		} while true

		var info = stat()

		guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else {
			Darwin.close(descriptor)
			throw receiving ? DCCTransferError.fileUnwritable : .fileUnreadable
		}

		return Reservation(
			descriptor: descriptor,
			path: candidate.path,
			size: UInt64(info.st_size),
			device: info.st_dev,
			inode: info.st_ino
		)
	}

	deinit {
		try? handle.close()
	}

	func size() throws -> UInt64 {
		var info = stat()
		var named = stat()
		guard !closed, fstat(handle.fileDescriptor, &info) == 0,
		      lstat(path, &named) == 0, named.st_dev == device, named.st_ino == inode,
		      named.st_mode & S_IFMT == S_IFREG, info.st_size >= 0
		else { throw writable ? DCCTransferError.fileUnwritable : .fileUnreadable }
		return UInt64(info.st_size)
	}

	func read(at offset: UInt64, count: Int) throws -> Data {
		try Task.checkCancellation()
		guard !closed, !writable else { throw DCCTransferError.fileUnreadable }
		do {
			try handle.seek(toOffset: offset)
			guard let data = try handle.read(upToCount: count), !data.isEmpty else {
				throw DCCTransferError.fileUnreadable
			}
			return data
		} catch { throw DCCTransferError.fileUnreadable }
	}

	func write(_ data: Data, at offset: UInt64) throws {
		try Task.checkCancellation()
		guard !closed, writable else { throw DCCTransferError.fileUnwritable }
		do {
			try handle.seek(toOffset: offset)
			try handle.write(contentsOf: data)
		} catch {
			let error = error as NSError
			if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOSPC) {
				throw DCCTransferError.storageFull
			}
			throw DCCTransferError.fileUnwritable
		}
	}

	func close() {
		guard !closed else { return }
		closed = true
		try? handle.close()
		accessLease = nil
		// Keep partials and empty reservations. A path identity check followed by
		// unlink is not atomic, so it cannot safely authorize deletion here.
	}
}
