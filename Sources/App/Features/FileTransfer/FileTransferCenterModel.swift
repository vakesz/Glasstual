/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Observation

enum FileTransferAction: Sendable {
	case start
	case stop
	case remove
	case open
	case reveal
	case preview
}

@Observable
final class FileTransferCenterModel {
	private(set) var transfers: [FileTransferController] = []
	var selection: Set<String> = []
	var previewSelection: URL? {
		didSet {
			if previewSelection == nil {
				previewAccessLeases.removeAll()
			}
		}
	}

	private var previewAccessLeases: [FileTransferAccessLease] = []

	/** Held while a share the row menu offered is still in the system's hands.

	 The share picker reads the file after the menu that offered it is gone, so
	 the scope cannot be a transient one taken around a `withAccess` call the
	 way Open, Reveal and Quick Look take theirs. */
	@ObservationIgnored private var shareAccessLeases: [FileTransferAccessLease] = []

	/** Which transfers have a readable local file, as of one presentation.

	 Answering costs a security-scope round trip and a `stat` per row, and a
	 single row menu asks four separate questions of it: whether Open, Reveal
	 and Quick Look apply, and what Share would hand over. */
	@ObservationIgnored private var localFileCache: (revision: Int, files: [String: FileTransferLocalFile?]) = (-1, [:])

	var isChoosingDestination = false
	var filter = FileTransferSelection.all {
		didSet { retainVisibleSelection() }
	}

	private var presentationRevision = 0

	var visibleTransfers: [FileTransferController] {
		_ = presentationRevision
		return filter.shownTransfers(in: transfers, isSender: \.isSender)
	}

	var stoppedTransfers: [FileTransferController] {
		transfers.filter { Self.stoppedStatuses.contains($0.transferStatus) }
	}

	var activeTransfers: [FileTransferController] {
		transfers.filter { [.receiving, .sending].contains($0.transferStatus) }
	}

	/** How many downloads are actually in flight or still waiting to start.

	 This is what the receiver limit bounds, so a completed, stopped or failed
	 row must not count towards it: those stay in the list until the user clears
	 them, and counting them spent the limit permanently — a session that had
	 finished a hundred and twenty downloads refused the next offer outright. */
	var receiverCount: Int {
		transfers.count { $0.isSender == false && Self.activeOrPendingStatuses.contains($0.transferStatus) }
	}

	/// How many bytes the downloads that are running or waiting still have left
	/// to write, which is what a new offer has to find room beside.
	var pendingReceiveByteCount: UInt64 {
		transfers.reduce(into: UInt64(0)) { total, transfer in
			guard transfer.isSender == false,
			      Self.activeOrPendingStatuses.contains(transfer.transferStatus),
			      transfer.totalFilesize > transfer.processedFilesize
			else { return }

			total += transfer.totalFilesize - transfer.processedFilesize
		}
	}

	var canClearStoppedTransfers: Bool {
		stoppedTransfers.isEmpty == false
	}

	func add(_ transfer: FileTransferController) {
		transfers.insert(transfer, at: 0)
		refreshPresentation()
	}

	func remove(_ removedTransfers: [FileTransferController]) {
		let identifiers = Set(removedTransfers.map(\.uniqueIdentifier))
		transfers.removeAll { identifiers.contains($0.uniqueIdentifier) }
		selection.subtract(identifiers)
		selectionDidChange()
		refreshPresentation()
	}

	func transfers(with identifiers: Set<String>) -> [FileTransferController] {
		transfers.filter { identifiers.contains($0.uniqueIdentifier) }
	}

	func contextSelection(for identifier: String) -> Set<String> {
		selection.contains(identifier) ? selection : [identifier]
	}

	func canPerform(_ action: FileTransferAction, on identifiers: Set<String>? = nil) -> Bool {
		let selected = transfers(with: identifiers ?? selection)
		guard selected.isEmpty == false else { return false }

		switch action {
		case .start:
			return selected.contains(where: \.canStart)
		case .stop:
			return selected.contains { Self.activeOrPendingStatuses.contains($0.transferStatus) }
		case .remove:
			return true
		case .open, .reveal:
			return selected.contains { hasLocalFile($0) }
		case .preview:
			return selected.allSatisfy { hasLocalFile($0) }
		}
	}

	func selectedFileURLs(for identifiers: Set<String>? = nil) -> [URL] {
		selectedLocalFiles(for: identifiers).map(\.url)
	}

	func selectedLocalFiles(for identifiers: Set<String>? = nil) -> [FileTransferLocalFile] {
		transfers(with: identifiers ?? selection).compactMap { localFile(of: $0) }
	}

	/// The files a share of `identifiers` puts in front of the user, with their
	/// access held for as long as the share can still read them.
	func shareableFileURLs(for identifiers: Set<String>) -> [URL] {
		let files = selectedLocalFiles(for: identifiers)
		shareAccessLeases = files.map { FileTransferAccessLease(url: $0.accessURL) }
		return files.map(\.url)
	}

	/// Ends the access the last share was offered. Nothing can reach the rows
	/// the share came from once the window is gone.
	func releaseShareAccess() {
		shareAccessLeases.removeAll()
	}

	var previewItems: [URL] {
		selectedFileURLs()
	}

	func presentPreview() {
		let files = selectedLocalFiles()
		previewAccessLeases = files.map { FileTransferAccessLease(url: $0.accessURL) }
		previewSelection = files.first?.url
	}

	func selectionDidChange() {
		guard previewSelection != nil else { return }
		let files = selectedLocalFiles()
		previewAccessLeases = files.map { FileTransferAccessLease(url: $0.accessURL) }
		let items = files.map(\.url)
		if let previewSelection, items.contains(previewSelection) {
			return
		}
		previewSelection = items.first
	}

	func refreshPresentation() {
		presentationRevision &+= 1
	}

	private func retainVisibleSelection() {
		selection.formIntersection(Set(visibleTransfers.map(\.uniqueIdentifier)))
	}

	private static let stoppedStatuses: Set<FileTransferStatus> = [
		.complete, .stopped, .fatalError, .recoverableError,
	]

	private static let activeOrPendingStatuses: Set<FileTransferStatus> = [
		.initializing,
		.connecting,
		.receiving,
		.isListeningAsSender,
		.isListeningAsReceiver,
		.sending,
		.mappingListeningPort,
		.waitingForLocalIPAddress,
		.waitingForReceiverToAccept,
		.waitingForResumeAccept,
	]

	private func hasLocalFile(_ transfer: FileTransferController) -> Bool {
		localFile(of: transfer) != nil
	}

	/// The transfer's readable local file, answered once per presentation.
	///
	/// Only the rows something asks about are looked up: the maintenance timer
	/// refreshes the presentation once a second while a transfer is running,
	/// and sweeping every row on each of those would cost far more than the
	/// repetition this is here to remove.
	private func localFile(of transfer: FileTransferController) -> FileTransferLocalFile? {
		if localFileCache.revision != presentationRevision {
			localFileCache = (presentationRevision, [:])
		}

		let identifier = transfer.uniqueIdentifier

		if let answered = localFileCache.files[identifier] {
			return answered
		}

		let file = Self.readableLocalFile(of: transfer)
		localFileCache.files[identifier] = file
		return file
	}

	private static func readableLocalFile(of transfer: FileTransferController) -> FileTransferLocalFile? {
		if transfer.isSender == false, transfer.transferStatus != .complete {
			return nil
		}

		guard let file = transfer.localFile,
		      file.withAccess({ FileManager.default.fileExists(atPath: $0.path) })
		else {
			return nil
		}

		return file
	}
}

struct FileTransferRowPresentation {
	enum Progress: Equatable {
		case hidden
		case indeterminate
		case determinate(value: UInt64, total: UInt64)
	}

	let filename: String
	let totalSize: String
	/// How much has arrived so far, written the way the row's sizes are. The
	/// accessibility value reads it, so it is not a raw byte count.
	let processedSize: String
	let status: String
	let progress: Progress

	init(transfer: FileTransferController) {
		filename = transfer.filename
		totalSize = Int64(clamping: transfer.totalFilesize).textualPaddedByteCountDescription
		processedSize = Int64(clamping: transfer.processedFilesize).textualPaddedByteCountDescription
		progress = switch transfer.transferStatus {
		case .connecting:
			.indeterminate
		case .receiving, .sending:
			.determinate(value: transfer.processedFilesize, total: transfer.totalFilesize)
		default:
			.hidden
		}

		if transfer.transferStatus == .complete, case .unacknowledged? = transfer.completion {
			status = FileTransferStrings.unacknowledgedCompletion(peerNickname: transfer.peerNickname)
		} else if [.fatalError, .recoverableError].contains(transfer.transferStatus) {
			status = transfer.errorMessageDescription ?? ""
		} else if [.sending, .receiving].contains(transfer.transferStatus) {
			status = Self.activeStatus(for: transfer, processedSize: processedSize, totalSize: totalSize)
		} else {
			status = FileTransferStrings.status(
				transfer.transferStatus,
				direction: transfer.isSender ? .outgoing : .incoming,
				peerNickname: transfer.peerNickname
			) ?? ""
		}
	}

	private static func activeStatus(
		for transfer: FileTransferController,
		processedSize: String,
		totalSize: String
	) -> String {
		let currentSpeed = averageSpeed(transfer.speedRecords)
		let speed = Int64(clamping: currentSpeed).textualPaddedByteCountDescription
		let timeRemaining: String? = if currentSpeed > 0,
		                                transfer.processedFilesize < transfer.totalFilesize
		{
			timeRemainingDescription(
				for: TimeInterval((transfer.totalFilesize - transfer.processedFilesize) / currentSpeed)
			)
		} else {
			nil
		}

		return FileTransferStrings.progress(
			direction: transfer.isSender ? .outgoing : .incoming,
			processedSize: processedSize,
			totalSize: totalSize,
			speed: speed,
			peerNickname: transfer.peerNickname,
			timeRemaining: timeRemaining
		)
	}

	private static func averageSpeed(_ records: [UInt64]) -> UInt64 {
		guard records.isEmpty == false else { return 0 }
		var total: UInt64 = 0
		for record in records {
			let (sum, overflow) = total.addingReportingOverflow(record)
			total = overflow ? .max : sum
		}
		return total / UInt64(records.count)
	}

	private static func timeRemainingDescription(for interval: TimeInterval) -> String? {
		guard interval > 0 else { return nil }
		let units = NSCalendar.Unit([.day, .hour, .minute, .second]).rawValue
		return humanReadableTimeInterval(interval, true, units) as String?
	}
}
