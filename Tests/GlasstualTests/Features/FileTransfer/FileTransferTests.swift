// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Darwin
import Foundation
@testable import Glasstual
import Synchronization
import Testing

@MainActor
@Suite("File transfer lifecycle", .serialized)
struct FileTransferTests {
	/// The list a transfer is listed in, which it reads the maintenance timer,
	/// this Mac's address and the tokens in use from. Held for the test because
	/// the transfer's reference back to it is weak.
	private let center = FileTransferStore(addressSource: { nil })

	@Test("A sender follows peer NICK changes while its source reservation is suspended", .timeLimit(.minutes(1)))
	func senderFollowsNicknameDuringReservation() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		try Data([7]).write(to: source)
		let file = try await DCCTransferFile.open(url: source, receiving: false)
		let (gate, release) = AsyncStream<Void>.makeStream()
		let (started, didStart) = AsyncStream<Void>.makeStream()
		defer { release.finish(); didStart.finish() }
		let session = TestServerSession()
		let preparation = Task {
			await FileTransfer.sender(for: session, center: center, nickname: "alice", path: source.path) { _, _, _ in
				didStart.yield(())
				for await _ in gate {}
				return file
			}
		}
		var iterator = started.makeAsyncIterator()
		_ = await iterator.next()
		try receiveNicknameChange(":alice!ali@example.org NICK :bob", on: session)
		try receiveNicknameChange(":bob!ali@example.org NICK :carol", on: session)
		release.finish()
		let controller = try #require(await preparation.value)
		#expect(controller.peerNickname == "carol")
		#expect(controller.ownedFile === file)
		assertOfferTargets("carol", from: controller, on: session)
		controller.prepareForPermanentDestruction()
		await controller.stopTask?.value
	}

	@Test("Peer NICK tracking applies inline and ends when a transfer is removed")
	func nicknameObservationLifetime() throws {
		let session = TestServerSession()
		let controller = try receiver(on: session)
		try receiveNicknameChange(":alice!ali@example.org NICK :mallory", on: TestServerSession())
		#expect(controller.peerNickname == "alice")
		try receiveNicknameChange(":alice!ali@example.org NICK :bob", on: session)
		#expect(controller.peerNickname == "bob")
		controller.prepareForPermanentDestruction()
		try receiveNicknameChange(":bob!ali@example.org NICK :carol", on: session)
		#expect(controller.peerNickname == "bob")
	}

	@Test("Cancelling a suspended sender closes a late source reservation", .timeLimit(.minutes(1)))
	func cancelledSenderClosesReservation() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		try Data([7]).write(to: source)
		let file = try await DCCTransferFile.open(url: source, receiving: false)
		let (gate, release) = AsyncStream<Void>.makeStream()
		let (started, didStart) = AsyncStream<Void>.makeStream()
		defer { release.finish(); didStart.finish() }
		let session = TestServerSession()
		let preparation = Task {
			await FileTransfer.sender(for: session, center: center, nickname: "alice", path: source.path) { _, _, _ in
				didStart.yield(())
				for await _ in gate {}
				return file
			}
		}
		var iterator = started.makeAsyncIterator()
		_ = await iterator.next()
		preparation.cancel()
		release.finish()
		#expect(await preparation.value == nil)
		await #expect(throws: DCCTransferError.fileUnreadable) { try await file.read(at: 0, count: 1) }
	}

	@Test("Closing during reservation releases a late descriptor instead of adopting it")
	func closedReservationCannotBeAdopted() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let file = try await DCCTransferFile.open(url: directory.appendingPathComponent("reserved"), receiving: true)
		let (gate, release) = AsyncStream<Void>.makeStream()
		let (started, didStart) = AsyncStream<Void>.makeStream()
		let session = TestServerSession()
		let controller = try receiver(on: session, size: 1)
		controller.path = directory.path
		controller.negotiation.fileFactory = { _, _, _ in
			didStart.yield(())
			for await _ in gate {}
			return file
		}
		let preparation = Task { await controller.claimDestinationFilename() }
		var iterator = started.makeAsyncIterator()
		_ = await iterator.next()
		controller.close()
		release.finish()
		await preparation.value
		#expect(controller.ownedFile == nil)
		await #expect(throws: DCCTransferError.fileUnreadable) { try await file.read(at: 0, count: 1) }
	}

	@Test("Empty files can be offered and accepted")
	func emptyFileFactories() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("empty")
		try Data().write(to: source)
		let session = TestServerSession()
		let outgoing = try #require(
			await FileTransfer.sender(for: session, center: center, nickname: "alice", path: source.path)
		)
		let incoming = try #require(FileTransfer.receiver(for: session, center: center, nickname: "alice",
		                                                  address: "127.0.0.1",
		                                                  port: 5000, filename: "empty", filesize: 0, token: nil))
		#expect(outgoing.totalFilesize == 0)
		#expect(incoming.totalFilesize == 0)
		outgoing.prepareForPermanentDestruction()
		incoming.prepareForPermanentDestruction()
		await outgoing.stopTask?.value
	}

	@Test("Completed rows release their source descriptors and scope leases", .timeLimit(.minutes(1)))
	func completedRowsReleaseFiles() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		let payload = TransferFixture.payload(byteCount: 1027)
		try payload.write(to: source)
		let counts = Mutex((started: 0, stopped: 0))
		let model = FileTransferList()
		let session = TestServerSession()
		var files: [DCCTransferFile] = []
		for index in 0 ..< 24 {
			let receiving = try DCCTransfer(config: TransferFixture.listeningReceiver(
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
			let controller = try receiver(on: session, size: UInt64(payload.count))
			controller.session = nil // Do not deliver OS notifications from this lifecycle test.
			controller.isSender = true
			controller.path = directory.path
			controller.filename = source.lastPathComponent
			controller.takeOwnership(of: file)
			controller.transferStatus = .connecting
			model.add(controller)
			let config = TransferFixture.diallingSender(
				port: port,
				file: file,
				fileSize: UInt64(payload.count)
			)
			controller.startTransfer(with: config)
			let sending = try #require(controller.negotiation.transferEvents)
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
		let controller = try receiver(on: TestServerSession())
		controller.session = nil
		controller.takeOwnership(of: file)
		let transfer = DCCTransfer(config: TransferFixture.listeningSender(file: file, fileSize: 1))
		controller.negotiation.transfer = transfer
		let (gate, continuation) = AsyncStream<Void>.makeStream()
		defer { continuation.finish() }
		controller.stopTask = Task {
			var iterator = gate.makeAsyncIterator()
			_ = await iterator.next()
		}
		controller.transferDidReport(.finished, from: transfer)
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
		let controller = try receiver(on: TestServerSession())
		controller.session = nil
		controller.takeOwnership(of: file)
		controller.path = directory.path
		controller.filename = destination.lastPathComponent
		controller.processedFilesize = 2
		controller.transferStatus = .waitingForResumeAccept
		let model = FileTransferList()
		model.add(controller)
		let (gate, continuation) = AsyncStream<Void>.makeStream()
		defer { continuation.finish() }
		controller.stopTask = Task {
			var iterator = gate.makeAsyncIterator()
			_ = await iterator.next()
		}

		controller.didReceiveResumeAccept(3)

		#expect(controller.transferStatus == .recoverableError)
		#expect(controller.ownedFile == nil)
		#expect(model.transfers.count == 1 && model.transfers.first === controller)
		#expect(model.canPerform(.start, on: [controller.uniqueIdentifier]))
		#expect(controller.negotiation.restartsFromBeginning)
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
		let controller = try receiver(on: TestServerSession())
		controller.session = nil
		controller.takeOwnership(of: file)
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
		let session = TestServerSession()
		let sender = try #require(
			await FileTransfer.sender(for: session, center: center, nickname: "alice", path: source.path)
		)
		sender.isReversed = false
		let config = try TransferFixture.listeningSender(
			file: #require(sender.ownedFile),
			fileSize: UInt64(payload.count)
		)
		let actor = DCCTransfer(config: config)
		sender.negotiation.transfer = actor
		await actor.start()
		var iterator = actor.events.makeAsyncIterator()
		guard case let .listening(port) = await iterator.next() else { Issue.record("Sender did not listen"); return }
		sender.hostPort = port
		sender.transferStatus = .isListeningAsSender
		sender.didReceiveResumeRequest(37003)
		await sender.negotiation.negotiationTask?.value
		#expect(sender.negotiation.transfer === actor)
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
		let receiver = DCCTransfer(config: incoming)
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
		let sender = try DCCTransfer(config: TransferFixture.listeningSender(
			file: TransferFixture.source(source),
			fileSize: UInt64(payload.count)
		))
		await sender.start()
		var iterator = sender.events.makeAsyncIterator()
		guard case let .listening(port) = await iterator.next() else { Issue.record("Sender did not listen"); return }
		let senderEvents = TransferFixture.collectEvents(from: sender)
		#expect(await sender.commitResumeOffset(37003))
		let session = TestServerSession()
		session.markAsLoggedIn()
		let receiver = try receiver(on: session, port: port, size: UInt64(payload.count))
		receiver.path = directory.path
		await receiver.claimDestinationFilename()
		let file = try #require(receiver.ownedFile)
		try await file.write(Data(payload.prefix(37003)), at: 0)
		receiver.open()
		await receiver.negotiation.filePreparationTask?.value
		await receiver.negotiation.negotiationTask?.value
		#expect(receiver.transferStatus == .waitingForResumeAccept)
		#expect(receiver.processedFilesize == 37003)
		receiver.didReceiveResumeAccept(37003)
		let receiving = try #require(receiver.negotiation.transferEvents)
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
		var config = TransferFixture.listeningReceiver(file: file, fileSize: UInt64(payload.count))
		config.resumeOffset = 37003
		let receiver = DCCTransfer(config: config)
		await receiver.start()
		var iterator = receiver.events.makeAsyncIterator()
		guard case let .listening(port) = await iterator.next() else { Issue.record("Receiver did not listen"); return }
		let receiving = TransferFixture.collectEvents(from: receiver)
		let session = TestServerSession()
		session.markAsLoggedIn()
		let sender = try #require(
			await FileTransfer.sender(for: session, center: center, nickname: "alice", path: source.path)
		)
		sender.isReversed = true
		sender.transferToken = "42"
		sender.transferStatus = .waitingForReceiverToAccept
		sender.didReceiveResumeRequest(37003)
		await sender.negotiation.negotiationTask?.value
		#expect(sender.processedFilesize == 37003)
		sender.didReceiveSendRequest("127.0.0.1", hostPort: port)
		#expect(await receiving.value.last.map(TransferFixture.isFinished) == true)
		await sender.negotiation.transferEvents?.value
		#expect(sender.transferStatus == .complete)
		#expect(sender.processedFilesize == UInt64(payload.count))
		#expect(try Data(contentsOf: URL(fileURLWithPath: file.path)) == payload)
		sender.prepareForPermanentDestruction()
		await file.close()
	}

	@Test("Stop during initialization cancels pending file preparation")
	func stopInitializing() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let session = TestServerSession()
		session.markAsLoggedIn()
		let transfer = try receiver(on: session)
		transfer.open(withPath: directory.path)
		#expect(transfer.transferStatus == .initializing)
		let pending = try #require(transfer.negotiation.filePreparationTask)
		let model = FileTransferList()
		model.add(transfer)
		#expect(model.canPerform(.stop, on: [transfer.uniqueIdentifier]))
		transfer.closeAndPostNotification(false)
		await pending.value
		#expect(transfer.negotiation.transfer == nil)
		#expect(transfer.transferStatus == .stopped)
		#expect(session.sentLines.count == 0)
		transfer.prepareForPermanentDestruction()
	}

	@Test("Destroying one recipient closes only its owned source")
	func recipientsOwnIndependentSources() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		try Data([1, 2, 3]).write(to: source)
		let session = TestServerSession()
		let first = try #require(
			await FileTransfer.sender(for: session, center: center, nickname: "alice", path: source.path)
		)
		let second = try #require(
			await FileTransfer.sender(for: session, center: center, nickname: "bob", path: source.path)
		)
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
		let session = TestServerSession()
		let controller = try receiver(on: session)
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let config = try TransferFixture.listeningReceiver(
			file: TransferFixture.destination(directory.appendingPathComponent("unused")),
			fileSize: 10
		)
		let retired = DCCTransfer(config: config)
		let current = DCCTransfer(config: config)
		controller.negotiation.transfer = retired
		controller.stopTransfer()
		await controller.stopTask?.value
		controller.negotiation.transfer = current
		controller.transferStatus = .connecting
		controller.transferDidReport(.progress(processedBytes: 9), from: retired)
		controller.transferDidReport(.finished, from: retired)
		#expect(controller.processedFilesize == 0)
		#expect(controller.transferStatus == .connecting)
		controller.prepareForPermanentDestruction()
	}

	@Test("Giving up on the address settles receivers as well as senders")
	func reverseReceiverLookupFailure() async throws {
		let center = FileTransferStore(addressSource: { nil })
		let receiver = try receiver(on: TestServerSession(), in: center, token: "42")
		receiver.transferStatus = .waitingForLocalIPAddress
		center.model.add(receiver)
		center.clearIPAddress()
		_ = await center.ipAddressLookup?.value
		#expect(receiver.transferStatus == .recoverableError)
		receiver.prepareForPermanentDestruction()
	}

	@Test("Accept uses the default destination and Download To asks for a one-off folder")
	func notificationUsesNormalDestination() throws {
		let destination = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let center = FileTransferStore(defaultDownloadDestinationURL: destination)
		let transfer = try receiver(on: TestServerSession(), in: center)
		center.model.add(transfer)
		center.model.filter = .sending
		#expect(center.respondToNotification(
			for: transfer.uniqueIdentifier,
			sessionIdentifier: transfer.sessionId,
			accept: false
		))
		#expect(center.model.filter == .all && center.model.selection == [transfer.uniqueIdentifier])
		#expect(!center.model.isChoosingDestination)
		#expect(center.respondToNotification(
			for: transfer.uniqueIdentifier,
			sessionIdentifier: transfer.sessionId,
			accept: true
		))
		#expect(!center.model.isChoosingDestination && center.pendingDestinationTransferIDs.isEmpty)
		#expect(transfer.path == destination.path)
		#expect(!center.respondToNotification(for: "stale", sessionIdentifier: nil, accept: true))
		#expect(!center.respondToNotification(for: transfer.uniqueIdentifier, sessionIdentifier: "other", accept: true))

		let oneOff = try receiver(on: TestServerSession(), in: center)
		center.model.add(oneOff)
		center.perform(.downloadTo, on: [oneOff.uniqueIdentifier])
		#expect(center.model.isChoosingDestination)
		#expect(center.pendingDestinationTransferIDs == [oneOff.uniqueIdentifier])
		#expect(oneOff.path == nil)
	}

	@Test("An ACKless completion stays explicit in the transfer row")
	func acklessRowStatus() throws {
		let transfer = try receiver(on: TestServerSession())
		transfer.isSender = true
		transfer.completion = .unacknowledged
		transfer.transferStatus = .complete
		let unacknowledged = String(localized: .FileTransfer.sentToWithoutAPeerAcknowledgement("alice"))
		#expect(FileTransferRowPresentation(transfer: transfer).status == unacknowledged)
		transfer.completion = .acknowledged
		#expect(FileTransferRowPresentation(transfer: transfer).status != unacknowledged)
	}

	private func receiveNicknameChange(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))
		session.forwardsProcessedMessages = true
		session.processIncomingMessage(message)
	}

	private func assertOfferTargets(_ nickname: String, from controller: FileTransfer, on session: TestServerSession) {
		/* The address an offer names comes from the file-transfer port on the
		 session's services, so this suite's own centre is what answers it. */
		session.environment.services.fileTransfers = center
		let methodKey = SettingsKeys.FileTransfers.ipAddressDetectionMethod
		let addressKey = SettingsKeys.FileTransfers.manuallyEnteredIPAddress
		let previousMethod = methodKey.storedValue
		let previousAddress = addressKey.storedValue
		defer {
			methodKey.storedValue = previousMethod
			addressKey.storedValue = previousAddress
		}
		methodKey.value = .manual
		addressKey.storedValue = "127.0.0.1"
		controller.isReversed = false
		controller.hostPort = 5000
		controller.sendTransferRequestToSession()
		let lines = session.sentLines.compactMap { $0 as? String }
		#expect(lines == ["PRIVMSG \(nickname) :\u{1}DCC SEND source 2130706433 5000 1\u{1}"])
	}

	private func receiver(on session: ServerSession, in center: FileTransferStore? = nil, port: UInt16 = 1234,
	                      size: UInt64 = 2048, token: String? = nil) throws -> FileTransfer
	{
		try #require(FileTransfer.receiver(
			for: session,
			center: center ?? self.center,
			nickname: "alice",
			address: "127.0.0.1",
			port: port,
			filename: "file.bin",
			filesize: size,
			token: token
		))
	}
}
