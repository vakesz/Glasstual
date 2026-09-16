/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Observation

/// Which transfer directions the window is showing.
enum FileTransferSelection: String, CaseIterable, Identifiable, Sendable {
	case all
	case sending
	case receiving

	var id: String {
		rawValue
	}

	func shownTransfers<Transfer>(
		in transfers: [Transfer],
		isSender: (Transfer) -> Bool
	) -> [Transfer] {
		switch self {
		case .all:
			transfers
		case .sending:
			transfers.filter(isSender)
		case .receiving:
			transfers.filter { isSender($0) == false }
		}
	}
}

enum FileTransferAction: Sendable {
	case start
	case stop
	case remove
	case open
	case reveal
	case preview
}

@Observable
final class FileTransferList {
	private(set) var transfers: [FileTransfer] = []
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

	var isChoosingDestination = false
	var filter = FileTransferSelection.all {
		didSet { retainVisibleSelection() }
	}

	var visibleTransfers: [FileTransfer] {
		filter.shownTransfers(in: transfers, isSender: \.isSender)
	}

	var stoppedTransfers: [FileTransfer] {
		transfers.filter { $0.transferStatus.isRunning == false }
	}

	var activeTransfers: [FileTransfer] {
		transfers.filter(\.transferStatus.isActive)
	}

	/** How many downloads are actually in flight or still waiting to start.

	 This is what the receiver limit bounds, so a completed, stopped or failed
	 row must not count towards it: those stay in the list until the user clears
	 them, and counting them spent the limit permanently — a session that had
	 finished a hundred and twenty downloads refused the next offer outright. */
	var receiverCount: Int {
		transfers.count { $0.isSender == false && $0.transferStatus.isRunning }
	}

	/// How many bytes the downloads that are running or waiting still have left
	/// to write, which is what a new offer has to find room beside.
	var pendingReceiveByteCount: UInt64 {
		transfers.reduce(into: UInt64(0)) { total, transfer in
			guard transfer.isSender == false,
			      transfer.transferStatus.isRunning,
			      transfer.totalFilesize > transfer.processedFilesize
			else { return }

			total += transfer.totalFilesize - transfer.processedFilesize
		}
	}

	var canClearStoppedTransfers: Bool {
		stoppedTransfers.isEmpty == false
	}

	func add(_ transfer: FileTransfer) {
		transfers.insert(transfer, at: 0)
	}

	func remove(_ removedTransfers: [FileTransfer]) {
		let identifiers = Set(removedTransfers.map(\.uniqueIdentifier))
		transfers.removeAll { identifiers.contains($0.uniqueIdentifier) }
		selection.subtract(identifiers)
		selectionDidChange()
	}

	func transfers(with identifiers: Set<String>) -> [FileTransfer] {
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
			return selected.contains { $0.transferStatus.isRunning }
		case .remove:
			return true
		case .open, .reveal:
			return selected.contains { localFile(of: $0) != nil }
		case .preview:
			return selected.allSatisfy { localFile(of: $0) != nil }
		}
	}

	/** What the button that starts `identifiers` should be called.

	 An offer that has arrived and not been answered is accepted, not started,
	 and a transfer that failed for a reason a retry can get past is tried
	 again. A mixed selection has no one answer, so it keeps the generic verb. */
	func startActionTitle(for identifiers: Set<String>? = nil) -> String {
		let startable = transfers(with: identifiers ?? selection).filter(\.canStart)
		if startable.isEmpty == false, startable.allSatisfy({ $0.transferStatus == .recoverableError }) {
			return String(localized: .FileTransfers.retryTransfer)
		}
		if startable.isEmpty == false, startable.allSatisfy({ $0.isSender == false && $0.transferStatus == .stopped }) {
			return String(localized: .FileTransfers.acceptTransfer)
		}
		return String(localized: .FileTransfers.startTransfer)
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

	private func retainVisibleSelection() {
		selection.formIntersection(Set(visibleTransfers.map(\.uniqueIdentifier)))
	}

	/// The transfer's local file, if there is one a menu item can act on.
	///
	/// A download that has not completed has nothing to open, and a file the
	/// user moved or deleted since is no longer there to reveal.
	private func localFile(of transfer: FileTransfer) -> FileTransferLocalFile? {
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

	init(transfer: FileTransfer) {
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
			status = String(localized: .FileTransfers.sentToWithoutAPeerAcknowledgement(transfer.peerNickname))
		} else if [.fatalError, .recoverableError].contains(transfer.transferStatus) {
			status = transfer.errorMessageDescription ?? ""
		} else if transfer.transferStatus.isActive {
			status = Self.activeStatus(for: transfer, processedSize: processedSize, totalSize: totalSize)
		} else {
			status = transfer.transferStatus.notice(
				direction: transfer.isSender ? .outgoing : .incoming,
				peerNickname: transfer.peerNickname
			) ?? ""
		}
	}

	private static func activeStatus(
		for transfer: FileTransfer,
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

		let direction: FileTransferDirection = transfer.isSender ? .outgoing : .incoming

		return direction.progressNotice(
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

		return DateFormatting.humanReadable(
			interval,
			shortValue: true,
			fields: [.day, .hour, .minute, .second]
		)
	}
}
