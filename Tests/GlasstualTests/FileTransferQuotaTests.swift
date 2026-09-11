/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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
	private func receiver(
		on client: IRCClient,
		filename: String,
		filesize: UInt64 = 1024
	) throws -> FileTransferController {
		try #require(FileTransferController.receiver(
			for: client,
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
		FileTransferStatus.complete, .stopped, .fatalError, .recoverableError,
	])
	func finishedRowsDoNotSpendTheLimit(_ status: FileTransferStatus) throws {
		let client = GLTTestClient()
		let model = FileTransferCenterModel()
		let transfer = try receiver(on: client, filename: "photo.jpg")
		model.add(transfer)

		transfer.transferStatus = status

		#expect(model.receiverCount == 0)
	}

	@Test(arguments: [
		FileTransferStatus.initializing, .connecting, .receiving, .isListeningAsReceiver,
		.waitingForResumeAccept, .waitingForLocalIPAddress,
	])
	func runningAndWaitingRowsSpendTheLimit(_ status: FileTransferStatus) throws {
		let client = GLTTestClient()
		let model = FileTransferCenterModel()
		let transfer = try receiver(on: client, filename: "photo.jpg")
		model.add(transfer)

		transfer.transferStatus = status

		#expect(model.receiverCount == 1)
	}

	/// The limit bounds downloads. What this side is sending is bounded by the
	/// files the user picked, and has never counted.
	@Test("Outgoing transfers are not receivers")
	func sendersDoNotSpendTheLimit() throws {
		let client = GLTTestClient()
		let model = FileTransferCenterModel()
		let transfer = try receiver(on: client, filename: "photo.jpg")
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
		let client = GLTTestClient()
		let model = FileTransferCenterModel()
		let running = try receiver(on: client, filename: "big.iso", filesize: 1000)
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
		let client = GLTTestClient()
		let model = FileTransferCenterModel()
		let running = try receiver(on: client, filename: "big.iso", filesize: 1000)
		running.transferStatus = .receiving
		running.processedFilesize = 4000
		model.add(running)

		#expect(model.pendingReceiveByteCount == 0)
	}

	@Test("A destination with no room refuses the offer")
	func afullVolumeRefusesTheOffer() {
		// Nothing on this machine has room for sixteen exabytes.
		#expect(FileTransferCenter.destination(NSTemporaryDirectory(), hasRoomFor: UInt64.max) == false)
	}

	@Test("A destination with room accepts the offer")
	func aVolumeWithRoomAcceptsTheOffer() {
		#expect(FileTransferCenter.destination(NSTemporaryDirectory(), hasRoomFor: 1024))
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

		#expect(FileTransferCenter.destination(path, hasRoomFor: 1024))
	}

	/// A destination the user has not chosen yet is not a full one either: there
	/// is nothing to measure until one is picked.
	@Test("A destination that was never chosen is not treated as full")
	func anUnsetDestinationIsNotTreatedAsFull() {
		#expect(FileTransferCenter.destination(nil, hasRoomFor: 1024))
		#expect(FileTransferCenter.destination("", hasRoomFor: 1024))
	}

	@Test("An offer of nothing needs no room")
	func anEmptyOfferNeedsNoRoom() {
		#expect(FileTransferCenter.destination(nil, hasRoomFor: 0))
		#expect(FileTransferCenter.destination(NSTemporaryDirectory(), hasRoomFor: 0))
	}
}
