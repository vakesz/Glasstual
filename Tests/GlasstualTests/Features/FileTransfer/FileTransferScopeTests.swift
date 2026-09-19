@testable import Glasstual
import Testing

/// DCC `RESUME`/`ACCEPT` carry a port and a filename and nothing else. Without
/// scoping, any user on any connected network could move the resume offset of
/// somebody else's transfer.
@Suite("File transfer scope")
@MainActor
struct FileTransferScopeTests {
	private let center = FileTransferStore(addressSource: { nil })

	private func session() -> TestServerSession {
		TestServerSession()
	}

	private func receiver(
		on session: ServerSession,
		nickname: String = "alice",
		filename: String = "photo.jpg",
		token: String? = nil
	) throws -> FileTransfer {
		try #require(FileTransfer.receiver(
			for: session,
			center: center,
			nickname: nickname,
			address: "203.0.113.5",
			port: 1234,
			filename: filename,
			filesize: 1024,
			token: token
		))
	}

	/** A `RESUME` or `ACCEPT` names the transfer either by the port it negotiated
	 or by a reverse transfer's token. One that names both, or neither, is not a
	 request about any transfer of ours — the connection prints it as invalid
	 rather than searching on whichever half it recognises. */
	@Test("A request naming both a port and a token, or neither, is about no transfer")
	func aRequestMustNameExactlyOneOfPortAndToken() throws {
		let session = session()
		let transfer = try receiver(on: session)
		transfer.transferStatus = .waitingForResumeAccept
		center.model.add(transfer)

		#expect(center.resumeAccepted(
			at: 512, on: session, peerNickname: "alice", filename: "photo.jpg", port: 1234, token: "42"
		) == false)
		#expect(center.resumeAccepted(
			at: 512, on: session, peerNickname: "alice", filename: "photo.jpg", port: 0, token: nil
		) == false)
		#expect(transfer.transferStatus == .waitingForResumeAccept)
	}

	/// The answer only means anything to the transfer that asked the question:
	/// an `ACCEPT` for one that is not waiting moves an offset nothing claimed.
	@Test("An ACCEPT is acted on only while the transfer it names is waiting for one")
	func anAcceptIsActedOnOnlyWhileWaiting() throws {
		let session = session()
		let transfer = try receiver(on: session)
		transfer.processedFilesize = 512
		center.model.add(transfer)

		#expect(center.resumeAccepted(
			at: 512, on: session, peerNickname: "alice", filename: "photo.jpg", port: 1234, token: nil
		) == false)
		#expect(transfer.isResume == false)

		transfer.transferStatus = .waitingForResumeAccept

		#expect(center.resumeAccepted(
			at: 512, on: session, peerNickname: "alice", filename: "photo.jpg", port: 1234, token: nil
		))
		#expect(transfer.isResume)
		transfer.prepareForPermanentDestruction()
	}

	/** A `SEND` answering a reverse offer of ours has to agree with the offer it
	 answers. One that names a different size is answering something else, and
	 acting on it would dial a peer for a file neither side agreed on. */
	@Test("A reverse offer is only accepted by a SEND that agrees about the file")
	func aReverseOfferIsAcceptedOnAgreement() throws {
		let session = session()
		let offer = try receiver(on: session, filename: "file.bin", token: "42")
		offer.isSender = true
		offer.transferStatus = .waitingForReceiverToAccept
		center.model.add(offer)

		#expect(center.sentOfferExists(withToken: "42", on: session, peerNickname: "alice", filename: "file.bin"))
		#expect(center.sentOfferExists(withToken: "43", on: session, peerNickname: "alice", filename: "file.bin") == false)

		#expect(center.sentOfferAccepted(
			withToken: "42", on: session, peerNickname: "alice", filename: "file.bin",
			address: "203.0.113.9", port: 5000, filesize: 999
		) == false)
		#expect(offer.hostPort == 1234)

		#expect(center.sentOfferAccepted(
			withToken: "42", on: session, peerNickname: "alice", filename: "file.bin",
			address: "203.0.113.9", port: 5000, filesize: 1024
		))
		#expect(offer.hostAddress == "203.0.113.9")
		#expect(offer.hostPort == 5000)
		offer.prepareForPermanentDestruction()
	}

	@Test("Reverse ACCEPT lookup matches a receiver, token, peer, session and wire filename")
	func reverseAcceptScope() throws {
		let session = session()
		let receiver = try receiver(on: session, filename: "file.bin", token: "42")
		receiver.filename = "file_1.bin"
		let sender = try self.receiver(on: session, filename: "file.bin", token: "42")
		sender.isSender = true
		center.model.add(receiver)
		center.model.add(sender)
		#expect(center.fileTransfer(
			matchingToken: "42",
			session: session,
			peerNickname: "alice",
			filename: "file.bin",
			isSender: false
		) === receiver)
		#expect(center.fileTransfer(
			matchingToken: "43",
			session: session,
			peerNickname: "alice",
			filename: "file.bin",
			isSender: false
		) == nil)
		#expect(center.fileTransfer(
			matchingToken: "42",
			session: session,
			peerNickname: "mallory",
			filename: "file.bin",
			isSender: false
		) == nil)
		#expect(center.fileTransfer(
			matchingToken: "42",
			session: TestServerSession(),
			peerNickname: "alice",
			filename: "file.bin",
			isSender: false
		) == nil)
		#expect(center.fileTransfer(
			matchingToken: "42",
			session: session,
			peerNickname: "alice",
			filename: "file_1.bin",
			isSender: false
		) == nil)
	}

	@Test("The negotiating peer matches")
	func negotiatingPeerMatches() throws {
		let session = session()
		let transfer = try receiver(on: session)

		#expect(FileTransferStore.transfer(
			transfer,
			belongsTo: session,
			peerNickname: "alice",
			filename: "photo.jpg"
		))
	}

	@Test("The nickname comparison follows IRC case rules")
	func nicknameComparisonIsCaseInsensitive() throws {
		let session = session()
		let transfer = try receiver(on: session)

		#expect(FileTransferStore.transfer(
			transfer,
			belongsTo: session,
			peerNickname: "ALICE",
			filename: "photo.jpg"
		))
	}

	@Test("Another user on the same network does not match")
	func otherPeerDoesNotMatch() throws {
		let session = session()
		let transfer = try receiver(on: session)

		#expect(FileTransferStore.transfer(
			transfer,
			belongsTo: session,
			peerNickname: "mallory",
			filename: "photo.jpg"
		) == false)
	}

	@Test("A different filename does not match")
	func otherFilenameDoesNotMatch() throws {
		let session = session()
		let transfer = try receiver(on: session)

		#expect(FileTransferStore.transfer(
			transfer,
			belongsTo: session,
			peerNickname: "alice",
			filename: "other.jpg"
		) == false)
	}

	@Test("The same nickname on another network does not match")
	func otherSessionDoesNotMatch() throws {
		let owningSession = session()
		let otherSession = session()
		let transfer = try receiver(on: owningSession)

		#expect(FileTransferStore.transfer(
			transfer,
			belongsTo: otherSession,
			peerNickname: "alice",
			filename: "photo.jpg"
		) == false)
	}

	@Test("Filenames are compared in the form that crossed the wire")
	func filenamesAreComparedSanitized() throws {
		let session = session()
		let transfer = try receiver(on: session, filename: "holiday:photo.jpg")

		#expect(FileTransferStore.transfer(
			transfer,
			belongsTo: session,
			peerNickname: "alice",
			filename: "holiday_photo.jpg"
		))
	}
}
