/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CryptoKit
import Foundation
@testable import Glasstual
import Network
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

		let sender = try DCCTransfer(configuration: TransferFixture.listeningSender(
			file: TransferFixture.source(source),
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

			let receiver = try DCCTransfer(configuration: TransferFixture.diallingReceiver(
				port: port,
				file: TransferFixture.destination(destination),
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
		let receiver = try DCCTransfer(configuration: TransferFixture.listeningReceiver(
			file: TransferFixture.destination(destination),
			fileSize: UInt64(payload.count)
		))

		var receiverEvents: [DCCTransferEvent] = []
		var senderEvents: Task<[DCCTransferEvent], Never>?

		await receiver.start()

		for await event in receiver.events {
			receiverEvents.append(event)

			switch event {
			case let .listening(port):
				let sender = try DCCTransfer(configuration: TransferFixture.diallingSender(
					port: port,
					file: TransferFixture.source(source),
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

		let sender = try DCCTransfer(configuration: TransferFixture.listeningSender(
			file: TransferFixture.source(source),
			fileSize: UInt64(payload.count)
		))

		var receiverEvents: Task<[DCCTransferEvent], Never>?

		await sender.start()

		for await event in sender.events {
			guard case let .listening(port) = event else {
				continue
			}

			let receiver = try DCCTransfer(configuration: TransferFixture.diallingReceiver(
				port: port,
				file: TransferFixture.destination(destination),
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

	@Test("A source that grows sends only the offered byte count", .timeLimit(.minutes(1)))
	func growingSourceIsBounded() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		let destination = directory.appendingPathComponent("destination")
		let payload = TransferFixture.payload(byteCount: 100_003)
		try payload.write(to: source)
		let sender = try DCCTransfer(configuration: TransferFixture.listeningSender(
			file: TransferFixture.source(source),
			fileSize: 70001
		))
		var receiverEvents: Task<[DCCTransferEvent], Never>?
		var events: [DCCTransferEvent] = []
		await sender.start()
		for await event in sender.events {
			events.append(event)
			if case let .listening(port) = event {
				let receiver = try DCCTransfer(configuration: TransferFixture.diallingReceiver(
					port: port,
					file: TransferFixture.destination(destination),
					fileSize: 70001
				))
				receiverEvents = TransferFixture.collectEvents(from: receiver)
				await receiver.start()
			}
		}
		#expect(events.last.map(TransferFixture.isFinished) == true)
		#expect(await receiverEvents?.value.last.map(TransferFixture.isFinished) == true)
		#expect(try Data(contentsOf: destination) == Data(payload.prefix(70001)))
	}

	@Test("RESUME commits into an already listening sender without rebinding", .timeLimit(.minutes(1)))
	func resumeListeningSender() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let payload = TransferFixture.payload(byteCount: 100_003)
		let source = directory.appendingPathComponent("source")
		let destination = directory.appendingPathComponent("destination")
		try payload.write(to: source)
		let file = try DCCTransferFile(url: destination, receiving: true)
		try await file.write(Data(payload.prefix(37003)), at: 0)
		let sender = try DCCTransfer(configuration: TransferFixture.listeningSender(
			file: TransferFixture.source(source),
			fileSize: UInt64(payload.count)
		))
		var receiverEvents: Task<[DCCTransferEvent], Never>?
		var listeningCount = 0
		var events: [DCCTransferEvent] = []
		await sender.start()
		for await event in sender.events {
			events.append(event)
			if case let .listening(port) = event {
				listeningCount += 1
				#expect(await sender.commitResumeOffset(37003))
				var configuration = TransferFixture.diallingReceiver(
					port: port,
					file: file,
					fileSize: UInt64(payload.count)
				)
				configuration.resumeOffset = 37003
				let receiver = DCCTransfer(configuration: configuration)
				receiverEvents = TransferFixture.collectEvents(from: receiver)
				await receiver.start()
			}
			if case .connected = event {
				#expect(await sender.commitResumeOffset(1) == false)
			}
		}
		#expect(listeningCount == 1)
		#expect(events.last.map(TransferFixture.isFinished) == true)
		#expect(await receiverEvents?.value.last.map(TransferFixture.isFinished) == true)
		#expect(try Data(contentsOf: destination) == payload)
		await file.close()
	}

	@Test("A listener with no accepting peer expires", .timeLimit(.minutes(1)))
	func acceptanceDeadline() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		try Data([1]).write(to: source)
		var configuration = try TransferFixture.listeningSender(file: TransferFixture.source(source), fileSize: 1)
		configuration.acceptanceTimeout = .milliseconds(100)
		let sender = DCCTransfer(configuration: configuration)
		let events = TransferFixture.collectEvents(from: sender)
		await sender.start()
		#expect(await events.value.last.flatMap(TransferFixture.failure) == .connectTimeout)
	}

	@Test("An idle connected sender cannot hold a receiver forever", .timeLimit(.minutes(1)))
	func receiverInactivityDeadline() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		var configuration = try TransferFixture.listeningReceiver(
			file: TransferFixture.destination(directory.appendingPathComponent("destination")),
			fileSize: 42
		)
		configuration.inactivityTimeout = .milliseconds(100)
		let receiver = DCCTransfer(configuration: configuration)
		var connection: NetworkConnection<TCP>?
		var events: [DCCTransferEvent] = []
		await receiver.start()
		for await event in receiver.events {
			events.append(event)
			if case let .listening(port) = event {
				let peer = try NetworkConnection(
					to: .hostPort(host: "127.0.0.1", port: #require(NWEndpoint.Port(rawValue: port))),
					using: .parameters { TCP() }
				)
				connection = peer
				try await peer.send(Data())
			}
		}
		#expect(events.last.flatMap(TransferFixture.failure) == .connectTimeout)
		withExtendedLifetime(connection) {}
	}

	@Test("ACKless close remains supported but is not called acknowledged", .timeLimit(.minutes(1)))
	func acklessCompletion() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		try Data(repeating: 7, count: 100_003).write(to: source)
		let sender = try DCCTransfer(configuration: TransferFixture.listeningSender(
			file: TransferFixture.source(source),
			fileSize: 100_003
		))
		var peerTask: Task<Void, Error>?
		var unacknowledged = false
		var events: [DCCTransferEvent] = []
		await sender.start()
		for await event in sender.events {
			events.append(event)
			if case let .listening(port) = event {
				peerTask = Task {
					let peer = NetworkConnection(
						to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
						using: .parameters { TCP() }
					)
					var count = 0
					while count < 100_003 {
						count += try await peer.receive(atLeast: 1, atMost: 65536).content.count
					}
					try await peer.send(Data(), endOfStream: true)
				}
			}
			if case .completion(.unacknowledged) = event {
				unacknowledged = true
			}
		}
		try await peerTask?.value
		#expect(unacknowledged)
		#expect(events.last.map(TransferFixture.isFinished) == true)
	}

	@Test("A truncated ACK followed by EOF is a failure", .timeLimit(.minutes(1)))
	func truncatedAcknowledgementFails() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		try Data([7]).write(to: source)
		let sender = try DCCTransfer(configuration: TransferFixture.listeningSender(
			file: TransferFixture.source(source),
			fileSize: 1
		))
		var peerTask: Task<Void, Error>?
		var events: [DCCTransferEvent] = []
		await sender.start()
		for await event in sender.events {
			events.append(event)
			if case let .listening(port) = event {
				peerTask = Task {
					let peer = NetworkConnection(
						to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
						using: .parameters { TCP() }
					)
					_ = try await peer.receive(atLeast: 1, atMost: 1)
					try await peer.send(Data([0, 0]), endOfStream: true)
				}
			}
		}
		try await peerTask?.value
		#expect(events.last.flatMap(TransferFixture.failure) == .closedByPeer)
	}

	@Test("A malformed ACK interrupts an in-flight sender", .timeLimit(.minutes(1)))
	func malformedAcknowledgementInterruptsSending() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		let size = 16 * 1024 * 1024
		try Data(repeating: 7, count: size).write(to: source)
		let sender = try DCCTransfer(configuration: TransferFixture.listeningSender(
			file: TransferFixture.source(source),
			fileSize: UInt64(size)
		))
		var peer: NetworkConnection<TCP>?
		var progress: UInt64 = 0
		var events: [DCCTransferEvent] = []
		await sender.start()
		for await event in sender.events {
			events.append(event)
			if case let .listening(port) = event {
				let connection = try NetworkConnection(
					to: .hostPort(host: "127.0.0.1", port: #require(NWEndpoint.Port(rawValue: port))),
					using: .parameters { TCP() }
				)
				peer = connection
				try await connection.send(DCCTransfer.acknowledgement(for: UInt64(size) + 1))
			}
			if case let .progress(bytes) = event {
				progress = bytes
			}
		}
		#expect(events.last.flatMap(TransferFixture.failure) == .badParameter)
		#expect(progress < UInt64(size))
		withExtendedLifetime(peer) {}
	}

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

	/// Reserves the file a transfer reads from. The transfer only ever uses
	/// the descriptor it is handed, so the test opens it the same way the
	/// application does.
	static func source(_ url: URL) throws -> DCCTransferFile {
		try DCCTransferFile(url: url, receiving: false)
	}

	/// Reserves the file a transfer writes into.
	static func destination(_ url: URL) throws -> DCCTransferFile {
		try DCCTransferFile(url: url, receiving: true)
	}

	static func listeningSender(file: DCCTransferFile, fileSize: UInt64) -> DCCTransfer.Configuration {
		DCCTransfer.Configuration(
			role: .sender,
			endpoint: .listen(portRange: portRange),
			file: file,
			fileSize: fileSize
		)
	}

	static func listeningReceiver(file: DCCTransferFile, fileSize: UInt64) -> DCCTransfer.Configuration {
		DCCTransfer.Configuration(
			role: .receiver,
			endpoint: .listen(portRange: portRange),
			file: file,
			fileSize: fileSize
		)
	}

	static func diallingReceiver(
		port: UInt16,
		file: DCCTransferFile,
		fileSize: UInt64
	) -> DCCTransfer.Configuration {
		DCCTransfer.Configuration(
			role: .receiver,
			endpoint: .connect(host: loopbackHost, port: port, interfaceName: nil, timeout: .seconds(20)),
			file: file,
			fileSize: fileSize
		)
	}

	static func diallingSender(
		port: UInt16,
		file: DCCTransferFile,
		fileSize: UInt64
	) -> DCCTransfer.Configuration {
		DCCTransfer.Configuration(
			role: .sender,
			endpoint: .connect(host: loopbackHost, port: port, interfaceName: nil, timeout: .seconds(20)),
			file: file,
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
