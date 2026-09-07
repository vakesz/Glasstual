/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Darwin
import Foundation
@testable import Glasstual
import Synchronization
import Testing

@MainActor
@Suite("DCC controller lifecycle", .serialized)
struct FileTransferControllerTests {
	@Test("Completed rows release their source descriptors and scope leases", .timeLimit(.minutes(1)))
	func completedRowsReleaseFiles() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		let payload = TransferFixture.payload(byteCount: 1027)
		try payload.write(to: source)
		let counts = Mutex((started: 0, stopped: 0))
		let model = FileTransferCenterModel()
		let client = GLTTestClient()
		var files: [DCCTransferFile] = []
		for index in 0 ..< 24 {
			let receiving = try DCCTransfer(configuration: TransferFixture.listeningReceiver(
				file: TransferFixture.destination(directory.appendingPathComponent("received-\(index)")),
				fileSize: UInt64(payload.count)
			))
			await receiving.start()
			var iterator = receiving.events.makeAsyncIterator()
			guard case let .listening(port) = await iterator.next() else {
				Issue.record("Receiver did not listen")
				await receiving.cancel()
				return
			}
			let receivedEvents = TransferFixture.collectEvents(from: receiving)
			let file = try DCCTransferFile(
				url: source, receiving: false,
				startAccess: { _ in counts.withLock { $0.started += 1 }; return true },
				stopAccess: { _ in counts.withLock { $0.stopped += 1 } }
			)
			files.append(file)
			#expect(try openDescriptorCount(for: source) == 1)
			let controller = try receiver(on: client, size: UInt64(payload.count))
			controller.client = nil // Do not deliver OS notifications from this lifecycle test.
			controller.isSender = true
			controller.path = directory.path
			controller.filename = source.lastPathComponent
			controller.ownedFile = file
			controller.transferStatus = .connecting
			model.add(controller)
			let configuration = TransferFixture.diallingSender(
				port: port,
				file: file,
				fileSize: UInt64(payload.count)
			)
			controller.startTransfer(with: configuration)
			let sending = try #require(controller.transferEvents)
			await sending.value
			await controller.stopTask?.value
			#expect(await receivedEvents.value.last.map(TransferFixture.isFinished) == true)
			#expect(controller.transferStatus == .complete)
			#expect(controller.ownedFile == nil)
			#expect(counts.withLock { $0.started == index + 1 && $0.stopped == index + 1 })
			#expect(try openDescriptorCount(for: source) == 0)
		}
		#expect(model.transfers.count == 24)
		for file in files {
			await #expect(throws: DCCTransferError.fileUnreadable) { try await file.read(at: 0, count: 1) }
		}
		model.selection = Set(model.transfers.map(\.uniqueIdentifier))
		let localFiles = model.selectedLocalFiles()
		#expect(localFiles.count == 24)
		#expect(localFiles.allSatisfy { $0.accessURL == source })
		let localFile = try #require(localFiles.first)
		#expect(try localFile.withAccess { try Data(contentsOf: $0) } == payload)
		#expect(try openDescriptorCount(for: source) == 0)
	}

	@Test("Completion releases the file only after earlier cancellation has drained")
	func completionWaitsForQuiescence() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		try Data([7]).write(to: source)
		let counts = Mutex((started: 0, stopped: 0))
		let file = try DCCTransferFile(
			url: source, receiving: false,
			startAccess: { _ in counts.withLock { $0.started += 1 }; return true },
			stopAccess: { _ in counts.withLock { $0.stopped += 1 } }
		)
		let controller = try receiver(on: GLTTestClient())
		controller.client = nil
		controller.ownedFile = file
		let transfer = DCCTransfer(configuration: TransferFixture.listeningSender(file: file, fileSize: 1))
		controller.transfer = transfer
		let (gate, continuation) = AsyncStream<Void>.makeStream()
		defer { continuation.finish() }
		controller.stopTask = Task {
			var iterator = gate.makeAsyncIterator()
			_ = await iterator.next()
		}
		controller.transferDidReport(.finished, from: transfer, sessionID: controller.sessionID)
		#expect(try await file.read(at: 0, count: 1) == Data([7]))
		#expect(counts.withLock { $0.started == 1 && $0.stopped == 0 })
		#expect(try openDescriptorCount(for: source) == 1)
		continuation.finish()
		await controller.stopTask?.value
		#expect(counts.withLock { $0.started == 1 && $0.stopped == 1 })
		#expect(try openDescriptorCount(for: source) == 0)
	}

	@Test("A fatal invalid RESUME keeps the row and partial but releases its file after cancellation drains")
	func fatalResumeReleasesPartial() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let destination = directory.appendingPathComponent("partial")
		let counts = Mutex((started: 0, stopped: 0))
		let file = try DCCTransferFile(
			url: destination, receiving: true, accessURL: directory,
			startAccess: { _ in counts.withLock { $0.started += 1 }; return true },
			stopAccess: { _ in counts.withLock { $0.stopped += 1 } }
		)
		try await file.write(Data([1, 2]), at: 0)
		let controller = try receiver(on: GLTTestClient())
		controller.client = nil
		controller.ownedFile = file
		controller.path = directory.path
		controller.filename = destination.lastPathComponent
		controller.processedFilesize = 2
		controller.transferStatus = .waitingForResumeAccept
		let model = FileTransferCenterModel()
		model.add(controller)
		let (gate, continuation) = AsyncStream<Void>.makeStream()
		defer { continuation.finish() }
		controller.stopTask = Task {
			var iterator = gate.makeAsyncIterator()
			_ = await iterator.next()
		}

		controller.didReceiveResumeAccept(3)

		#expect(controller.transferStatus == .fatalError)
		#expect(controller.ownedFile == nil)
		#expect(model.transfers.count == 1 && model.transfers.first === controller)
		#expect(!model.canPerform(.start, on: [controller.uniqueIdentifier]))
		#expect(try await file.size() == 2)
		#expect(counts.withLock { $0.started == 1 && $0.stopped == 0 })
		#expect(try openDescriptorCount(for: destination) == 1)
		continuation.finish()
		await controller.stopTask?.value
		#expect(counts.withLock { $0.started == 1 && $0.stopped == 1 })
		#expect(try openDescriptorCount(for: destination) == 0)
		#expect(try Data(contentsOf: destination) == Data([1, 2]))
		#expect(model.transfers.count == 1 && model.transfers.first === controller)
		controller.prepareForPermanentDestruction()
		await controller.stopTask?.value
		#expect(counts.withLock { $0.stopped == 1 })
	}

	@Test("Stopped and recoverable partials keep their descriptor and scope for retry", arguments: [false, true])
	func stoppedPartialsRetainFiles(recoverable: Bool) async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let destination = directory.appendingPathComponent("partial")
		let counts = Mutex((started: 0, stopped: 0))
		let file = try DCCTransferFile(
			url: destination, receiving: true, accessURL: directory,
			startAccess: { _ in counts.withLock { $0.started += 1 }; return true },
			stopAccess: { _ in counts.withLock { $0.stopped += 1 } }
		)
		try await file.write(Data([1, 2]), at: 0)
		let controller = try receiver(on: GLTTestClient())
		controller.client = nil
		controller.ownedFile = file
		controller.transferStatus = recoverable ? .recoverableError : .receiving
		controller.closeAndPostNotification(false)
		await controller.stopTask?.value
		#expect(controller.ownedFile === file)
		#expect(counts.withLock { $0.started == 1 && $0.stopped == 0 })
		#expect(try openDescriptorCount(for: destination) == 1)
		#expect(try await file.size() == 2)
		try await file.write(Data([3]), at: 2)
		controller.prepareForPermanentDestruction()
		await controller.stopTask?.value
		#expect(counts.withLock { $0.started == 1 && $0.stopped == 1 })
		#expect(try openDescriptorCount(for: destination) == 0)
		#expect(try Data(contentsOf: destination) == Data([1, 2, 3]))
	}

	private func openDescriptorCount(for url: URL) throws -> Int {
		let path = url.resolvingSymlinksInPath().path
		return try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").compactMap(Int32.init)
			.count { descriptor in
				var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
				guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else { return false }
				return String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) == path
			}
	}

	@Test("An active sender controller commits RESUME into its existing listener", .timeLimit(.minutes(1)))
	func activeSenderCommitsOffset() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		let payload = TransferFixture.payload(byteCount: 100_003)
		try payload.write(to: source)
		let client = GLTTestClient()
		let sender = try #require(FileTransferController.sender(for: client, nickname: "alice", path: source.path))
		sender.isReversed = false
		let configuration = try TransferFixture.listeningSender(
			file: #require(sender.ownedFile),
			fileSize: UInt64(payload.count)
		)
		let actor = DCCTransfer(configuration: configuration)
		sender.transfer = actor
		await actor.start()
		var iterator = actor.events.makeAsyncIterator()
		guard case let .listening(port) = await iterator.next() else { Issue.record("Sender did not listen"); return }
		sender.hostPort = port
		sender.transferStatus = .isListeningAsSender
		sender.didReceiveResumeRequest(37003)
		await sender.negotiationTask?.value
		#expect(sender.transfer === actor)
		#expect(sender.hostPort == port)
		#expect(sender.processedFilesize == 37003)
		let sending = TransferFixture.collectEvents(from: actor)
		let file = try DCCTransferFile(url: directory.appendingPathComponent("destination"), receiving: true)
		try await file.write(Data(payload.prefix(37003)), at: 0)
		var incoming = TransferFixture.diallingReceiver(
			port: port,
			file: file,
			fileSize: UInt64(payload.count)
		)
		incoming.resumeOffset = 37003
		let receiver = DCCTransfer(configuration: incoming)
		let receiving = TransferFixture.collectEvents(from: receiver)
		await receiver.start()
		#expect(await receiving.value.last.map(TransferFixture.isFinished) == true)
		#expect(await sending.value.last.map(TransferFixture.isFinished) == true)
		#expect(try Data(contentsOf: URL(fileURLWithPath: file.path)) == payload)
		sender.prepareForPermanentDestruction()
		await sender.stopTask?.value
		await file.close()
	}

	@Test("A receiver negotiates its owned partial and receives the resumed bytes", .timeLimit(.minutes(1)))
	func receiverResumesOwnedPartial() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		let payload = TransferFixture.payload(byteCount: 100_003)
		try payload.write(to: source)
		let sender = try DCCTransfer(configuration: TransferFixture.listeningSender(
			file: TransferFixture.source(source),
			fileSize: UInt64(payload.count)
		))
		await sender.start()
		var iterator = sender.events.makeAsyncIterator()
		guard case let .listening(port) = await iterator.next() else { Issue.record("Sender did not listen"); return }
		let senderEvents = TransferFixture.collectEvents(from: sender)
		#expect(await sender.commitResumeOffset(37003))
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let receiver = try receiver(on: client, port: port, size: UInt64(payload.count))
		receiver.path = directory.path
		receiver.claimDestinationFilename()
		let file = try #require(receiver.ownedFile)
		try await file.write(Data(payload.prefix(37003)), at: 0)
		receiver.open()
		await receiver.negotiationTask?.value
		#expect(receiver.transferStatus == .waitingForResumeAccept)
		#expect(receiver.processedFilesize == 37003)
		receiver.didReceiveResumeAccept(37003)
		let receiving = try #require(receiver.transferEvents)
		await receiving.value
		#expect(receiver.transferStatus == .complete)
		#expect(receiver.processedFilesize == UInt64(payload.count))
		#expect(await senderEvents.value.last.map(TransferFixture.isFinished) == true)
		#expect(try Data(contentsOf: URL(fileURLWithPath: file.path)) == payload)
		receiver.prepareForPermanentDestruction()
	}

	@Test("A reverse sender keeps the accepted resume offset when SEND supplies the address", .timeLimit(.minutes(1)))
	func reverseSenderKeepsOffset() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let payload = TransferFixture.payload(byteCount: 100_003)
		let source = directory.appendingPathComponent("source")
		try payload.write(to: source)
		let file = try DCCTransferFile(url: directory.appendingPathComponent("destination"), receiving: true)
		try await file.write(Data(payload.prefix(37003)), at: 0)
		var configuration = TransferFixture.listeningReceiver(file: file, fileSize: UInt64(payload.count))
		configuration.resumeOffset = 37003
		let receiver = DCCTransfer(configuration: configuration)
		await receiver.start()
		var iterator = receiver.events.makeAsyncIterator()
		guard case let .listening(port) = await iterator.next() else { Issue.record("Receiver did not listen"); return }
		let receiving = TransferFixture.collectEvents(from: receiver)
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let sender = try #require(FileTransferController.sender(for: client, nickname: "alice", path: source.path))
		sender.isReversed = true
		sender.transferToken = "42"
		sender.transferStatus = .waitingForReceiverToAccept
		sender.didReceiveResumeRequest(37003)
		await sender.negotiationTask?.value
		#expect(sender.processedFilesize == 37003)
		sender.didReceiveSendRequest("127.0.0.1", hostPort: port)
		#expect(await receiving.value.last.map(TransferFixture.isFinished) == true)
		await sender.transferEvents?.value
		#expect(sender.transferStatus == .complete)
		#expect(sender.processedFilesize == UInt64(payload.count))
		#expect(try Data(contentsOf: URL(fileURLWithPath: file.path)) == payload)
		sender.prepareForPermanentDestruction()
		await file.close()
	}

	@Test("Stop during initialization cancels pending negotiation")
	func stopInitializing() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let transfer = try receiver(on: client)
		transfer.open(withPath: directory.path)
		#expect(transfer.transferStatus == .initializing)
		let pending = transfer.negotiationTask
		let model = FileTransferCenterModel()
		model.add(transfer)
		#expect(model.canPerform(.stop, on: [transfer.uniqueIdentifier]))
		transfer.closeAndPostNotification(false)
		await pending?.value
		#expect(transfer.transfer == nil)
		#expect(transfer.transferStatus == .stopped)
		#expect(client.sentLines.count == 0)
		transfer.prepareForPermanentDestruction()
	}

	@Test("Destroying one recipient closes only its owned source")
	func recipientsOwnIndependentSources() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		try Data([1, 2, 3]).write(to: source)
		let client = GLTTestClient()
		let first = try #require(FileTransferController.sender(for: client, nickname: "alice", path: source.path))
		let second = try #require(FileTransferController.sender(for: client, nickname: "bob", path: source.path))
		let firstFile = try #require(first.ownedFile)
		let secondFile = try #require(second.ownedFile)
		first.prepareForPermanentDestruction()
		await first.stopTask?.value
		await #expect(throws: DCCTransferError.fileUnreadable) { try await firstFile.read(at: 0, count: 3) }
		#expect(try await secondFile.read(at: 0, count: 3) == Data([1, 2, 3]))
		second.prepareForPermanentDestruction()
		await second.stopTask?.value
	}

	@Test("Retired actor events cannot change a replacement session")
	func retiredEventsAreIgnored() async throws {
		let client = GLTTestClient()
		let controller = try receiver(on: client)
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let configuration = try TransferFixture.listeningReceiver(
			file: TransferFixture.destination(directory.appendingPathComponent("unused")),
			fileSize: 10
		)
		let retired = DCCTransfer(configuration: configuration)
		let current = DCCTransfer(configuration: configuration)
		let retiredID = controller.sessionID
		controller.transfer = retired
		controller.stopTransfer()
		await controller.stopTask?.value
		controller.transfer = current
		controller.transferStatus = .connecting
		controller.transferDidReport(.progress(processedBytes: 9), from: retired, sessionID: retiredID)
		controller.transferDidReport(.finished, from: retired, sessionID: retiredID)
		#expect(controller.processedFilesize == 0)
		#expect(controller.transferStatus == .connecting)
		controller.prepareForPermanentDestruction()
	}

	@Test("Reverse address lookup failure settles receivers as well as senders")
	func reverseReceiverLookupFailure() throws {
		let center = FileTransferCenter()
		let receiver = try receiver(on: GLTTestClient(), token: "42")
		receiver.transferStatus = .waitingForLocalIPAddress
		center.model.add(receiver)
		center.internetAddressLookupFailed()
		#expect(receiver.transferStatus == .recoverableError)
		receiver.prepareForPermanentDestruction()
	}

	@Test("Notification Accept asks for the normal destination and body click only selects")
	func notificationUsesNormalDestination() throws {
		let center = FileTransferCenter()
		let transfer = try receiver(on: GLTTestClient())
		center.model.add(transfer)
		center.model.filter = .sending
		#expect(center.respondToNotification(
			for: transfer.uniqueIdentifier,
			clientIdentifier: transfer.clientId,
			accept: false
		))
		#expect(center.model.filter == .all)
		#expect(center.model.selection == [transfer.uniqueIdentifier])
		#expect(!center.model.isChoosingDestination)
		#expect(center.respondToNotification(
			for: transfer.uniqueIdentifier,
			clientIdentifier: transfer.clientId,
			accept: true
		))
		#expect(center.model.isChoosingDestination)
		#expect(center.pendingDestinationTransferIDs == [transfer.uniqueIdentifier])
		#expect(transfer.path == nil)
		#expect(!center.respondToNotification(for: "stale", clientIdentifier: nil, accept: true))
		#expect(!center.respondToNotification(for: transfer.uniqueIdentifier, clientIdentifier: "other", accept: true))
	}

	@Test("Reverse ACCEPT lookup matches a receiver, token, peer, client and wire filename")
	func reverseAcceptScope() throws {
		let center = FileTransferCenter()
		let client = GLTTestClient()
		let receiver = try receiver(on: client, token: "42")
		receiver.filename = "file_1.bin"
		let sender = try self.receiver(on: client, token: "42")
		sender.isSender = true
		center.model.add(receiver)
		center.model.add(sender)
		#expect(center.fileTransfer(
			matchingToken: "42",
			client: client,
			peerNickname: "alice",
			filename: "file.bin",
			isSender: false
		) === receiver)
		#expect(center.fileTransfer(
			matchingToken: "43",
			client: client,
			peerNickname: "alice",
			filename: "file.bin",
			isSender: false
		) == nil)
		#expect(center.fileTransfer(
			matchingToken: "42",
			client: client,
			peerNickname: "mallory",
			filename: "file.bin",
			isSender: false
		) == nil)
		#expect(center.fileTransfer(
			matchingToken: "42",
			client: GLTTestClient(),
			peerNickname: "alice",
			filename: "file.bin",
			isSender: false
		) == nil)
		#expect(center.fileTransfer(
			matchingToken: "42",
			client: client,
			peerNickname: "alice",
			filename: "file_1.bin",
			isSender: false
		) == nil)
	}

	@Test("An ACKless completion stays explicit in the transfer row")
	func acklessRowStatus() throws {
		let transfer = try receiver(on: GLTTestClient())
		transfer.isSender = true
		transfer.completion = .unacknowledged
		transfer.transferStatus = .complete
		#expect(FileTransferRowPresentation(transfer: transfer).status == FileTransferStrings
			.unacknowledgedCompletion(peerNickname: "alice"))
		transfer.completion = .acknowledged
		#expect(FileTransferRowPresentation(transfer: transfer).status != FileTransferStrings
			.unacknowledgedCompletion(peerNickname: "alice"))
	}

	private func receiver(on client: IRCClient, port: UInt16 = 1234, size: UInt64 = 2048,
	                      token: String? = nil) throws -> FileTransferController
	{
		try #require(FileTransferController.receiver(
			for: client,
			nickname: "alice",
			address: "127.0.0.1",
			port: port,
			filename: "file.bin",
			filesize: size,
			token: token
		))
	}
}
