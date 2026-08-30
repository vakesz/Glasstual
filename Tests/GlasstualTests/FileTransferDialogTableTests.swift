@testable import Glasstual
import Testing

/// The file transfer table used to be an `NSArrayController` with an
/// `isSender ==` filter predicate, and it drew whatever `arrangedObjects` gave
/// back. Both halves are Swift now: the toolbar selection decides which
/// transfers are shown, and the table diffs them by `uniqueIdentifier`.
@Suite("File transfer dialog table")
@MainActor
struct FileTransferDialogTableTests {
	private struct Transfer: Equatable {
		let name: String
		let isSender: Bool
	}

	private let sending = Transfer(name: "outgoing", isSender: true)
	private let receiving = Transfer(name: "incoming", isSender: false)
	private let alsoSending = Transfer(name: "outgoing-2", isSender: true)

	private var everything: [Transfer] {
		[sending, receiving, alsoSending]
	}

	// MARK: - Which transfers the toolbar shows

	@Test("Every transfer is shown when nothing is filtered out")
	func allShowsEverything() {
		#expect(
			FileTransferSelection.all.shownTransfers(in: everything, isSender: \.isSender)
				== everything
		)
	}

	@Test("Sending shows only the transfers this side is sending")
	func sendingShowsOnlySenders() {
		#expect(
			FileTransferSelection.sending.shownTransfers(in: everything, isSender: \.isSender)
				== [sending, alsoSending]
		)
	}

	@Test("Receiving shows only the transfers this side is receiving")
	func receivingShowsOnlyReceivers() {
		#expect(
			FileTransferSelection.receiving.shownTransfers(in: everything, isSender: \.isSender)
				== [receiving]
		)
	}

	@Test("A selection that matches nothing leaves an empty table")
	func aSelectionMatchingNothingIsEmpty() {
		#expect(
			FileTransferSelection.receiving.shownTransfers(
				in: [sending, alsoSending],
				isSender: \.isSender
			).isEmpty
		)
	}

	@Test("Filtering keeps the order the transfers were added in")
	func filteringKeepsOrder() {
		let ordered = [alsoSending, receiving, sending]

		#expect(
			FileTransferSelection.sending.shownTransfers(in: ordered, isSender: \.isSender)
				== [alsoSending, sending]
		)
	}

	// MARK: - Real transfers

	@Test("The filter reads the direction off a real transfer")
	func filterReadsRealTransfers() throws {
		let client = GLTTestClient()
		let incoming = try transfer(on: client, filename: "photo.jpg")
		let outgoing = try transfer(on: client, filename: "notes.txt")
		outgoing.isSender = true

		let all = [incoming, outgoing]

		#expect(
			FileTransferSelection.sending.shownTransfers(in: all, isSender: \.isSender)
				== [outgoing]
		)
		#expect(
			FileTransferSelection.receiving.shownTransfers(in: all, isSender: \.isSender)
				== [incoming]
		)
	}

	@Test("Each transfer carries a distinct identity for the table to diff on")
	func transfersHaveDistinctIdentifiers() throws {
		let client = GLTTestClient()
		let first = try transfer(on: client, filename: "photo.jpg")
		let second = try transfer(on: client, filename: "photo.jpg")

		#expect(first.uniqueIdentifier.isEmpty == false)
		#expect(first.uniqueIdentifier != second.uniqueIdentifier)

		/* The identity has to survive being read twice, or a snapshot would
		 replace every row on every apply. */
		#expect(first.uniqueIdentifier == first.uniqueIdentifier)
	}

	@Test("Removing transfers by identity keeps the order of the rest")
	func removingByIdentityKeepsOrder() throws {
		let client = GLTTestClient()
		let first = try transfer(on: client, filename: "one.jpg")
		let second = try transfer(on: client, filename: "two.jpg")
		let third = try transfer(on: client, filename: "three.jpg")

		var stored = [first, second, third]
		let removed = Set([second].map(\.uniqueIdentifier))
		stored.removeAll { removed.contains($0.uniqueIdentifier) }

		#expect(stored == [first, third])
	}

	private func transfer(
		on client: IRCClient,
		filename: String
	) throws -> TDCFileTransferDialogTransferController {
		try #require(TDCFileTransferDialogTransferController.receiver(
			for: client,
			nickname: "alice",
			address: "203.0.113.5",
			port: 1234,
			filename: filename,
			filesize: 1024,
			token: nil
		))
	}
}
