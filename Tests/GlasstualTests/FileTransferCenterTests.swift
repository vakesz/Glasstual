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

	// MARK: - Real transfers

	@Test("The filter reads the direction off a real transfer")
	func filterReadsRealTransfers() throws {
		let client = TestClient()
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
		let client = TestClient()
		let first = try transfer(on: client, filename: "photo.jpg")
		let second = try transfer(on: client, filename: "photo.jpg")

		#expect(first.uniqueIdentifier.isEmpty == false)
		#expect(first.uniqueIdentifier != second.uniqueIdentifier)
	}

	@Test("Removing transfers by identity keeps the order of the rest")
	func removingByIdentityKeepsOrder() throws {
		let client = TestClient()
		let first = try transfer(on: client, filename: "one.jpg")
		let second = try transfer(on: client, filename: "two.jpg")
		let third = try transfer(on: client, filename: "three.jpg")

		let model = FileTransferList()
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
		let client = TestClient()
		let incoming = try transfer(on: client, filename: "incoming.jpg")
		let outgoing = try transfer(on: client, filename: "outgoing.jpg")
		outgoing.isSender = true

		let model = FileTransferList()
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
		let client = TestClient()
		let transfer = try transfer(on: client, filename: "archive.zip")

		let presentation = FileTransferRowPresentation(transfer: transfer)

		#expect(presentation.filename == "archive.zip")
		#expect(presentation.totalSize.isEmpty == false)
		#expect(presentation.status.isEmpty == false)
		#expect(presentation.progress == .hidden)
	}

	/// The status groups used to be spelled out as a set literal at every place
	/// that asked, so a new status could be left out of one of them.
	@Test("Every status belongs to exactly one of running, finished and idle")
	func statusPredicatesPartitionTheEnum() {
		let statuses: [FileTransferStatus] = [
			.complete, .connecting, .fatalError, .initializing, .isListeningAsReceiver,
			.isListeningAsSender, .mappingListeningPort, .receiving, .recoverableError, .sending,
			.stopped, .waitingForLocalIPAddress, .waitingForReceiverToAccept, .waitingForResumeAccept,
		]
		for status in statuses {
			#expect(!(status.isActive && status.isNegotiating), "\(status) is both active and negotiating")
			#expect(status.isRunning == (status.isActive || status.isNegotiating))
			#expect(!(status.isRunning && status.isFinished), "\(status) is both running and finished")
		}
		#expect(statuses.filter(\.isActive) == [.receiving, .sending])
		#expect(statuses.filter(\.isFinished) == [.complete, .fatalError, .recoverableError])
		#expect(statuses.filter(\.canRetry) == [.recoverableError, .stopped])
		#expect(
			statuses.filter(\.isAwaitingAddress)
				== [.initializing, .mappingListeningPort, .waitingForLocalIPAddress]
		)
	}

	@Test("The start button says what starting the selection would actually do")
	func startActionTitleFollowsTheSelection() throws {
		let client = TestClient()
		let offered = try transfer(on: client, filename: "offered.jpg")
		let failed = try transfer(on: client, filename: "failed.jpg")
		failed.transferStatus = .recoverableError
		let model = FileTransferList()
		model.add(offered)
		model.add(failed)

		#expect(model.startActionTitle(for: [offered.uniqueIdentifier]) == String(localized: .FileTransfers.acceptTransfer))
		#expect(model.startActionTitle(for: [failed.uniqueIdentifier]) == String(localized: .FileTransfers.retryTransfer))
		/* Two rows that would do different things share the generic verb. */
		#expect(
			model.startActionTitle(for: [offered.uniqueIdentifier, failed.uniqueIdentifier])
				== String(localized: .FileTransfers.startTransfer)
		)
		/* An outgoing offer is started, never "accepted". */
		offered.isSender = true
		#expect(model.startActionTitle(for: [offered.uniqueIdentifier]) == String(localized: .FileTransfers.startTransfer))
	}

	private func transfer(
		on client: Client,
		filename: String
	) throws -> FileTransfer {
		try #require(FileTransfer.receiver(
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
