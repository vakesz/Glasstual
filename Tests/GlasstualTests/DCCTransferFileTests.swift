/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Darwin
import Foundation
@testable import Glasstual
import Testing

@Suite("DCC owned files")
struct DCCTransferFileTests {
	@Test("Simultaneous offers reserve distinct files, including dangling symlinks")
	func exclusiveReservations() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let url = directory.appendingPathComponent("file.bin")
		try FileManager.default.createSymbolicLink(
			at: url,
			withDestinationURL: directory.appendingPathComponent("absent")
		)
		let files = try await withThrowingTaskGroup(of: DCCTransferFile.self) { group in
			for _ in 0 ..< 12 {
				group.addTask { try DCCTransferFile(url: url, receiving: true) }
			}
			var files: [DCCTransferFile] = []
			for try await file in group {
				files.append(file)
			}
			return files
		}
		#expect(Set(files.map(\.path)).count == 12)
		#expect(files.allSatisfy { $0.path != url.path })
		#expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("absent").path))
		for file in files {
			await file.close()
		}
	}

	@Test("Replacing the destination path cannot redirect writes or authorize resume")
	func replacedDestination() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let url = directory.appendingPathComponent("file.bin")
		let moved = directory.appendingPathComponent("partial.bin")
		let file = try DCCTransferFile(url: url, receiving: true)
		try await file.write(Data([1, 2]), at: 0)
		try FileManager.default.moveItem(at: url, to: moved)
		try Data([9, 9, 9]).write(to: url)
		try await file.write(Data([3]), at: 2)
		await #expect(throws: DCCTransferError.fileUnwritable) { try await file.size() }
		await file.close()
		#expect(try Data(contentsOf: moved) == Data([1, 2, 3]))
		#expect(try Data(contentsOf: url) == Data([9, 9, 9]))
	}

	@Test("Source identity is pinned before its pathname is replaced")
	func pinnedSource() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let url = directory.appendingPathComponent("file.bin")
		try Data([1, 2, 3]).write(to: url)
		let file = try DCCTransferFile(url: url, receiving: false)
		try FileManager.default.removeItem(at: url)
		try Data([9, 9, 9]).write(to: url)
		#expect(try await file.read(at: 0, count: 3) == Data([1, 2, 3]))
		await file.close()
	}

	@Test("Closing preserves both partials and empty reservations")
	func closePreservesFiles() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let url = directory.appendingPathComponent("file.bin")
		let first = try DCCTransferFile(url: url, receiving: true)
		let second = try DCCTransferFile(url: url, receiving: true)
		try await first.write(Data([1, 2, 3]), at: 0)
		await first.close()
		await second.close()
		#expect(try Data(contentsOf: URL(fileURLWithPath: first.path)) == Data([1, 2, 3]))
		#expect(try Data(contentsOf: URL(fileURLWithPath: second.path)).isEmpty)
	}

	@Test("ACK framing tolerates split and coalesced frames and UInt32 wrap")
	func acknowledgementFraming() throws {
		let offset = UInt64(UInt32.max) - 3
		var parser = DCCAcknowledgements(offset: offset, offeredSize: offset + 8)
		let frames = DCCTransfer.acknowledgement(for: offset + 4) + DCCTransfer.acknowledgement(for: offset + 8)
		try parser.append(Data(frames.prefix(1)))
		#expect(!parser.isComplete)
		try parser.append(Data(frames.dropFirst().prefix(5)))
		#expect(!parser.isComplete)
		try parser.append(Data(frames.suffix(2)))
		#expect(parser.isComplete)
	}

	@Test("ACKs cannot move backwards or beyond the offer")
	func invalidAcknowledgements() throws {
		var backwards = DCCAcknowledgements(offset: 100, offeredSize: 200)
		#expect(throws: DCCTransferError.badParameter) { try backwards.append(DCCTransfer.acknowledgement(for: 99)) }
		var oversized = DCCAcknowledgements(offset: 0, offeredSize: 200)
		#expect(throws: DCCTransferError.badParameter) { try oversized.append(DCCTransfer.acknowledgement(for: 201)) }
	}

	@Test("A FIFO source is rejected without blocking the offer", .timeLimit(.minutes(1)))
	func nonregularSource() throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let url = directory.appendingPathComponent("pipe")
		#expect(mkfifo(url.path, S_IRUSR | S_IWUSR) == 0)
		#expect(throws: DCCTransferError.fileUnreadable) { try DCCTransferFile(url: url, receiving: false) }
	}

	@Test("A collision suffix fits even when the offered name fills NAME_MAX")
	func longCollisionName() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let url = directory.appendingPathComponent(String(repeating: "a", count: 251) + ".bin")
		let first = try DCCTransferFile(url: url, receiving: true)
		let second = try DCCTransferFile(url: url, receiving: true)
		#expect(first.path != second.path)
		#expect(URL(fileURLWithPath: second.path).lastPathComponent.utf8.count <= 255)
		await first.close()
		await second.close()
	}

	@Test("Timeout cancels the operation before returning to its owner", .timeLimit(.minutes(1)))
	func writeDeadlineCancelsOperation() async {
		let (events, continuation) = AsyncStream<Bool>.makeStream()
		await #expect(throws: DCCTransferError.writeTimeout) {
			try await DCCTransfer.withTimeout(.milliseconds(50), failingWith: .writeTimeout) {
				defer { continuation.yield(Task.isCancelled); continuation.finish() }
				try await Task.sleep(for: .seconds(60))
			}
		}
		var iterator = events.makeAsyncIterator()
		#expect(await iterator.next() == true)
	}
}
