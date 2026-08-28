@testable import Glasstual
import Testing

/// DCC `RESUME`/`ACCEPT` carry a port and a filename and nothing else. Without
/// scoping, any user on any connected network could move the resume offset of
/// somebody else's transfer.
@Suite("File transfer scope")
@MainActor
struct FileTransferScopeTests {
	private func client() -> GLTTestClient {
		GLTTestClient()
	}

	private func receiver(
		on client: IRCClient,
		nickname: String = "alice",
		filename: String = "photo.jpg"
	) throws -> TDCFileTransferDialogTransferController {
		try #require(TDCFileTransferDialogTransferController.receiver(
			for: client,
			nickname: nickname,
			address: "203.0.113.5",
			port: 1234,
			filename: filename,
			filesize: 1024,
			token: nil
		))
	}

	@Test("The negotiating peer matches")
	func negotiatingPeerMatches() throws {
		let client = client()
		let transfer = try receiver(on: client)

		#expect(FileTransferDialog.transfer(
			transfer,
			belongsTo: client,
			peerNickname: "alice",
			filename: "photo.jpg"
		))
	}

	@Test("The nickname comparison follows IRC case rules")
	func nicknameComparisonIsCaseInsensitive() throws {
		let client = client()
		let transfer = try receiver(on: client)

		#expect(FileTransferDialog.transfer(
			transfer,
			belongsTo: client,
			peerNickname: "ALICE",
			filename: "photo.jpg"
		))
	}

	@Test("Another user on the same network does not match")
	func otherPeerDoesNotMatch() throws {
		let client = client()
		let transfer = try receiver(on: client)

		#expect(FileTransferDialog.transfer(
			transfer,
			belongsTo: client,
			peerNickname: "mallory",
			filename: "photo.jpg"
		) == false)
	}

	@Test("A different filename does not match")
	func otherFilenameDoesNotMatch() throws {
		let client = client()
		let transfer = try receiver(on: client)

		#expect(FileTransferDialog.transfer(
			transfer,
			belongsTo: client,
			peerNickname: "alice",
			filename: "other.jpg"
		) == false)
	}

	@Test("The same nickname on another network does not match")
	func otherClientDoesNotMatch() throws {
		let owningClient = client()
		let otherClient = client()
		let transfer = try receiver(on: owningClient)

		#expect(FileTransferDialog.transfer(
			transfer,
			belongsTo: otherClient,
			peerNickname: "alice",
			filename: "photo.jpg"
		) == false)
	}

	@Test("Filenames are compared in the form that crossed the wire")
	func filenamesAreComparedSanitized() throws {
		let client = client()
		let transfer = try receiver(on: client, filename: "holiday:photo.jpg")

		#expect(FileTransferDialog.transfer(
			transfer,
			belongsTo: client,
			peerNickname: "alice",
			filename: "holiday_photo.jpg"
		))
	}
}
