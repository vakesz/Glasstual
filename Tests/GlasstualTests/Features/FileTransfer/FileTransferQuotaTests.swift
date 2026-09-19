// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** What the file-transfer list will and will not take on.

 Two limits guard it, and both used to be measured against the wrong thing. The
 receiver limit counted every row ever added, including the finished ones that
 stay in the list until the user clears them, so it was spent permanently. The
 free-space check did not exist: a download was reserved and started, and the
 volume being full was something the last block found out. */
@MainActor
@Suite("File transfer quotas")
struct FileTransferQuotaTests {
	private let center = FileTransferStore(addressSource: { nil })

	private func receiver(
		on session: ServerSession,
		filename: String,
		filesize: UInt64 = 1024
	) throws -> FileTransfer {
		try #require(FileTransfer.receiver(
			for: session,
			center: center,
			nickname: "alice",
			address: "203.0.113.5",
			port: 1234,
			filename: filename,
			filesize: filesize,
			token: nil
		))
	}

	/// A finished download is a row the user has yet to clear, not a download.
	@Test(arguments: [
		FileTransferStatus.complete, .fatalError, .recoverableError,
	])
	func finishedRowsDoNotSpendTheLimit(_ status: FileTransferStatus) throws {
		let session = TestServerSession()
		let model = FileTransferList()
		let transfer = try receiver(on: session, filename: "photo.jpg")
		model.add(transfer)

		transfer.transferStatus = status

		#expect(model.receiverCount == 0)
	}

	@Test(arguments: [
		FileTransferStatus.stopped, .initializing, .connecting, .receiving, .isListeningAsReceiver,
		.waitingForResumeAccept, .waitingForLocalIPAddress,
	])
	func runningAndWaitingRowsSpendTheLimit(_ status: FileTransferStatus) throws {
		let session = TestServerSession()
		let model = FileTransferList()
		let transfer = try receiver(on: session, filename: "photo.jpg")
		model.add(transfer)

		transfer.transferStatus = status

		#expect(model.receiverCount == 1)
	}

	@Test("Unanswered offers stop at the receiver limit and clearing one admits another")
	func unansweredOffersAreBounded() throws {
		let session = TestServerSession()
		func offer(_ index: Int) -> String? {
			center.addReceiver(
				for: session, nickname: "alice", address: "203.0.113.5", port: 1234,
				filename: "offer-\(index).jpg", filesize: 1024, token: nil, peerIsKnown: false
			)
		}

		for index in 0 ..< FileTransferConstants.receiverHardLimit {
			#expect(offer(index) != nil)
		}
		#expect(offer(FileTransferConstants.receiverHardLimit) == nil)
		#expect(center.model.transfers.count == FileTransferConstants.receiverHardLimit)

		let removed = try #require(center.model.transfers.first)
		center.perform(.remove, on: [removed.uniqueIdentifier])

		#expect(offer(FileTransferConstants.receiverHardLimit + 1) != nil)
		#expect(center.model.receiverCount == FileTransferConstants.receiverHardLimit)
	}

	/// The limit bounds downloads. What this side is sending is bounded by the
	/// files the user picked, and has never counted.
	@Test("Outgoing transfers are not receivers")
	func sendersDoNotSpendTheLimit() throws {
		let session = TestServerSession()
		let model = FileTransferList()
		let transfer = try receiver(on: session, filename: "photo.jpg")
		transfer.isSender = true
		transfer.transferStatus = .sending
		model.add(transfer)

		#expect(model.receiverCount == 0)
	}

	/** The room a new offer needs is its own size plus what the downloads
	 already running still have to write — they are all writing to the same
	 volume at the same time, so a check against one offer at a time would let
	 a hundred of them agree they each fit. */
	@Test("Outstanding bytes count towards the next offer's room")
	func outstandingBytesAreCounted() throws {
		let session = TestServerSession()
		let model = FileTransferList()
		let running = try receiver(on: session, filename: "big.iso", filesize: 1000)
		running.transferStatus = .receiving
		running.processedFilesize = 400
		model.add(running)

		#expect(model.pendingReceiveByteCount == 600)

		running.transferStatus = .complete

		// A finished download has already written its bytes; they are not pending.
		#expect(model.pendingReceiveByteCount == 0)
	}

	/// A transfer that somehow reports more written than announced must not
	/// wrap the unsigned subtraction into a demand for sixteen exabytes.
	@Test("An over-long transfer reports no outstanding bytes")
	func overLongTransfersDoNotUnderflow() throws {
		let session = TestServerSession()
		let model = FileTransferList()
		let running = try receiver(on: session, filename: "big.iso", filesize: 1000)
		running.transferStatus = .receiving
		running.processedFilesize = 4000
		model.add(running)

		#expect(model.pendingReceiveByteCount == 0)
	}

	@Test("A destination with no room refuses the offer")
	func afullVolumeRefusesTheOffer() {
		// Nothing on this machine has room for sixteen exabytes.
		#expect(FileTransferStore.destination(NSTemporaryDirectory(), hasRoomFor: UInt64.max) == false)
	}

	@Test("A destination with room accepts the offer")
	func aVolumeWithRoomAcceptsTheOffer() {
		#expect(FileTransferStore.destination(NSTemporaryDirectory(), hasRoomFor: 1024))
	}

	/** A volume that will not answer — a network mount, a path under a mount
	 point that is not there — is not evidence of being full. The transfer is
	 allowed to try and to fail the ordinary way rather than being refused on a
	 guess. */
	@Test("A destination whose volume cannot answer is not treated as full")
	func anUnanswerableDestinationIsNotTreatedAsFull() {
		let path = "/Volumes/\(UUID().uuidString)/Downloads"

		/* This is only a test of the fallback if the lookup really fails. A path
		 that happened to resolve would be measuring a volume that answered, and
		 an empty one would not reach the lookup at all. */
		#expect(throws: (any Error).self) {
			try URL(fileURLWithPath: path)
				.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
		}

		#expect(FileTransferStore.destination(path, hasRoomFor: 1024))
	}

	/// A destination the user has not chosen yet is not a full one either: there
	/// is nothing to measure until one is picked.
	@Test("A destination that was never chosen is not treated as full")
	func anUnsetDestinationIsNotTreatedAsFull() {
		#expect(FileTransferStore.destination(nil, hasRoomFor: 1024))
		#expect(FileTransferStore.destination("", hasRoomFor: 1024))
	}

	@Test("An offer of nothing needs no room")
	func anEmptyOfferNeedsNoRoom() {
		#expect(FileTransferStore.destination(nil, hasRoomFor: 0))
		#expect(FileTransferStore.destination(NSTemporaryDirectory(), hasRoomFor: 0))
	}
}
