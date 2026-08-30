/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CryptoKit
import Foundation
@testable import Glasstual
import Testing

/// Drives two `DCCTransfer` actors against each other over the loopback
/// interface, which is the only way to prove the transfer end to end without a
/// peer on the network.
@Suite("DCC transfer over loopback")
struct DCCTransferLoopbackTests {
	// MARK: - The transfers

	@Test("A five megabyte file arrives byte for byte", .timeLimit(.minutes(1)))
	func fiveMegabyteFileSurvivesTheRoundTrip() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }

		let payload = TransferFixture.payload(byteCount: 5 * 1024 * 1024)
		let source = directory.appendingPathComponent("source.bin")
		let destination = directory.appendingPathComponent("destination.bin")
		try payload.write(to: source)

		let sender = DCCTransfer(configuration: TransferFixture.listeningSender(
			filePath: source.path,
			fileSize: UInt64(payload.count)
		))

		var senderEvents: [DCCTransferEvent] = []
		var receiverEvents: Task<[DCCTransferEvent], Never>?

		await sender.start()

		for await event in sender.events {
			senderEvents.append(event)

			guard case let .listening(port) = event else {
				continue
			}

			let receiver = DCCTransfer(configuration: TransferFixture.diallingReceiver(
				port: port,
				filePath: destination.path,
				fileSize: UInt64(payload.count)
			))
			receiverEvents = TransferFixture.collectEvents(from: receiver)
			await receiver.start()
		}

		let received = try #require(await receiverEvents?.value)

		#expect(senderEvents.last.map(TransferFixture.isFinished) == true)
		#expect(received.last.map(TransferFixture.isFinished) == true)

		let delivered = try Data(contentsOf: destination)
		#expect(delivered.count == payload.count)
		#expect(SHA256.hash(data: delivered) == SHA256.hash(data: payload))
	}

	@Test("Cancelling a transfer ends its events without a verdict", .timeLimit(.minutes(1)))
	func cancellingATransferEndsItsEventsWithoutAVerdict() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }

		let payload = TransferFixture.payload(byteCount: 5 * 1024 * 1024)
		let source = directory.appendingPathComponent("source.bin")
		let destination = directory.appendingPathComponent("destination.bin")
		try payload.write(to: source)

		/* The receiver listens so that the side under test is the one this
		 loop is driving: it has to be cancelled part-way through. */
		let receiver = DCCTransfer(configuration: TransferFixture.listeningReceiver(
			filePath: destination.path,
			fileSize: UInt64(payload.count)
		))

		var receiverEvents: [DCCTransferEvent] = []
		var senderEvents: Task<[DCCTransferEvent], Never>?

		await receiver.start()

		for await event in receiver.events {
			receiverEvents.append(event)

			switch event {
			case let .listening(port):
				let sender = DCCTransfer(configuration: TransferFixture.diallingSender(
					port: port,
					filePath: source.path,
					fileSize: UInt64(payload.count)
				))
				senderEvents = TransferFixture.collectEvents(from: sender)
				await sender.start()
			case .progress:
				await receiver.cancel()
			default:
				break
			}
		}

		_ = await senderEvents?.value

		#expect(receiverEvents.contains { TransferFixture.isProgress($0) })
		#expect(receiverEvents.contains { TransferFixture.isFinished($0) } == false)
		#expect(receiverEvents.contains { TransferFixture.failure($0) != nil } == false)

		let delivered = try Data(contentsOf: destination)
		#expect(delivered.count < payload.count)
	}

	@Test("A peer that sends more than it announced is cut off at the cap", .timeLimit(.minutes(1)))
	func aPeerThatOvershootsIsCutOffAtTheCap() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }

		let payload = TransferFixture.payload(byteCount: 512 * 1024)
		let source = directory.appendingPathComponent("source.bin")
		let destination = directory.appendingPathComponent("destination.bin")
		try payload.write(to: source)

		/* The receiver was told the file is one byte shorter than the sender
		 will actually push, so the last block overshoots the announced size. */
		let announcedSize = UInt64(payload.count) - 1

		let sender = DCCTransfer(configuration: TransferFixture.listeningSender(
			filePath: source.path,
			fileSize: UInt64(payload.count)
		))

		var receiverEvents: Task<[DCCTransferEvent], Never>?

		await sender.start()

		for await event in sender.events {
			guard case let .listening(port) = event else {
				continue
			}

			let receiver = DCCTransfer(configuration: TransferFixture.diallingReceiver(
				port: port,
				filePath: destination.path,
				fileSize: announcedSize
			))
			receiverEvents = TransferFixture.collectEvents(from: receiver)
			await receiver.start()
		}

		let received = try #require(await receiverEvents?.value)

		#expect(received.last.flatMap(TransferFixture.failure) == .oversizedTransfer)

		let delivered = try Data(contentsOf: destination)
		#expect(UInt64(delivered.count) == announcedSize)
	}

	// MARK: - The acknowledgement

	@Test(
		"The acknowledgement is the running total as a big-endian 32-bit count",
		arguments: [
			(UInt64(0), Data([0, 0, 0, 0])),
			(UInt64(1), Data([0, 0, 0, 1])),
			(UInt64(65536), Data([0, 1, 0, 0])),
			(UInt64(UInt32.max), Data([255, 255, 255, 255])),
			/* Past four gigabytes the count wraps, which is what the protocol
				says to do rather than something this implementation invented. */
			(UInt64(UInt32.max) + 2, Data([0, 0, 0, 1])),
		]
	)
	func acknowledgementCarriesTheRunningTotal(byteCount: UInt64, expected: Data) {
		#expect(DCCTransfer.acknowledgement(for: byteCount) == expected)
	}
}

/// Shared scaffolding for the loopback transfers.
enum TransferFixture {
	static let loopbackHost = "127.0.0.1"
	/// A range well clear of anything a developer machine is likely to serve.
	static let portRange: ClosedRange<UInt16> = 49250 ... 49450

	static func makeDirectory() throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("DCCTransferTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		return directory
	}

	static func remove(_ directory: URL) {
		try? FileManager.default.removeItem(at: directory)
	}

	/// Deterministic filler: a checksum only proves anything if the bytes vary.
	static func payload(byteCount: Int) -> Data {
		var data = Data(count: byteCount)

		data.withUnsafeMutableBytes { buffer in
			for index in 0 ..< byteCount {
				buffer[index] = UInt8(truncatingIfNeeded: index &* 31 &+ 7)
			}
		}

		return data
	}

	static func listeningSender(filePath: String, fileSize: UInt64) -> DCCTransfer.Configuration {
		DCCTransfer.Configuration(
			role: .sender,
			endpoint: .listen(portRange: portRange),
			filePath: filePath,
			fileSize: fileSize
		)
	}

	static func listeningReceiver(filePath: String, fileSize: UInt64) -> DCCTransfer.Configuration {
		DCCTransfer.Configuration(
			role: .receiver,
			endpoint: .listen(portRange: portRange),
			filePath: filePath,
			fileSize: fileSize
		)
	}

	static func diallingReceiver(
		port: UInt16,
		filePath: String,
		fileSize: UInt64
	) -> DCCTransfer.Configuration {
		DCCTransfer.Configuration(
			role: .receiver,
			endpoint: .connect(host: loopbackHost, port: port, interfaceName: nil, timeout: .seconds(20)),
			filePath: filePath,
			fileSize: fileSize
		)
	}

	static func diallingSender(
		port: UInt16,
		filePath: String,
		fileSize: UInt64
	) -> DCCTransfer.Configuration {
		DCCTransfer.Configuration(
			role: .sender,
			endpoint: .connect(host: loopbackHost, port: port, interfaceName: nil, timeout: .seconds(20)),
			filePath: filePath,
			fileSize: fileSize
		)
	}

	/// Drains the other side's events concurrently: only one consumer may read
	/// an `AsyncStream`, and the test body is busy with its own side.
	static func collectEvents(from transfer: DCCTransfer) -> Task<[DCCTransferEvent], Never> {
		let events = transfer.events

		return Task {
			var collected: [DCCTransferEvent] = []

			for await event in events {
				collected.append(event)
			}

			return collected
		}
	}

	static func isFinished(_ event: DCCTransferEvent) -> Bool {
		if case .finished = event {
			return true
		}

		return false
	}

	static func isProgress(_ event: DCCTransferEvent) -> Bool {
		if case .progress = event {
			return true
		}

		return false
	}

	static func failure(_ event: DCCTransferEvent) -> DCCTransferError? {
		guard case let .failed(error) = event else {
			return nil
		}

		return error
	}
}
