@testable import Glasstual
import SwiftUI
import Testing

/// The dialog used to split its state between an `NSArrayController`, a table
/// data source and the transfer controllers' weak references to AppKit cells.
/// The SwiftUI list now projects one observable model instead.
@Suite("File transfer dialog")
@MainActor
struct FileTransferCenterTests {
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
				.map(\.uniqueIdentifier) == [outgoing.uniqueIdentifier]
		)
		#expect(
			FileTransferSelection.receiving.shownTransfers(in: all, isSender: \.isSender)
				.map(\.uniqueIdentifier) == [incoming.uniqueIdentifier]
		)
	}

	@Test("Each transfer carries a distinct identity for the table to diff on")
	func transfersHaveDistinctIdentifiers() throws {
		let client = GLTTestClient()
		let first = try transfer(on: client, filename: "photo.jpg")
		let second = try transfer(on: client, filename: "photo.jpg")

		#expect(first.uniqueIdentifier.isEmpty == false)
		#expect(first.uniqueIdentifier != second.uniqueIdentifier)
	}

	@Test("Removing transfers by identity keeps the order of the rest")
	func removingByIdentityKeepsOrder() throws {
		let client = GLTTestClient()
		let first = try transfer(on: client, filename: "one.jpg")
		let second = try transfer(on: client, filename: "two.jpg")
		let third = try transfer(on: client, filename: "three.jpg")

		let model = FileTransferCenterModel()
		model.add(first)
		model.add(second)
		model.add(third)

		/* `add` puts the newest transfer first, which is the order the list
		 shows; removal has to leave the rest of that order alone. */
		#expect(model.transfers.map(\.uniqueIdentifier) == [third, second, first].map(\.uniqueIdentifier))

		model.remove([second])

		#expect(model.transfers.map(\.uniqueIdentifier) == [third, first].map(\.uniqueIdentifier))
		#expect(model.visibleTransfers.map(\.uniqueIdentifier) == [third, first].map(\.uniqueIdentifier))
	}

	@Test("The model owns newest-first ordering, filtering, and selection")
	func modelOwnsListState() throws {
		let client = GLTTestClient()
		let incoming = try transfer(on: client, filename: "incoming.jpg")
		let outgoing = try transfer(on: client, filename: "outgoing.jpg")
		outgoing.isSender = true

		let model = FileTransferCenterModel()
		model.add(incoming)
		model.add(outgoing)
		#expect(
			model.visibleTransfers.map(\.uniqueIdentifier)
				== [outgoing.uniqueIdentifier, incoming.uniqueIdentifier]
		)

		model.selection = [incoming.uniqueIdentifier, outgoing.uniqueIdentifier]
		model.filter = .receiving
		#expect(model.visibleTransfers.map(\.uniqueIdentifier) == [incoming.uniqueIdentifier])
		#expect(model.selection == [incoming.uniqueIdentifier])

		model.remove([incoming])
		#expect(model.visibleTransfers.isEmpty)
		#expect(model.selection.isEmpty)
	}

	@Test("Rows project transfer state without retaining a view")
	func rowPresentationIsAValueSnapshot() throws {
		let client = GLTTestClient()
		let transfer = try transfer(on: client, filename: "archive.zip")

		let presentation = FileTransferRowPresentation(transfer: transfer)

		#expect(presentation.filename == "archive.zip")
		#expect(presentation.totalSize.isEmpty == false)
		#expect(presentation.status.isEmpty == false)
		#expect(presentation.progress == .hidden)
	}

	@Test("The feature ships no legacy nib")
	func featureUsesNativeSwiftUI() {
		#expect(Bundle.main.path(forResource: "TDCFileTransferDialog", ofType: "nib") == nil)
	}

	private func transfer(
		on client: IRCClient,
		filename: String
	) throws -> FileTransferController {
		try #require(FileTransferController.receiver(
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
