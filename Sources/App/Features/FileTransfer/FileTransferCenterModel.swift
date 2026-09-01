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
	var previewSelection: URL?
	var isChoosingDestination = false
	var filter = FileTransferSelection.all {
		didSet { retainVisibleSelection() }
	}

	private var presentationRevision = 0

	var visibleTransfers: [FileTransferController] {
		_ = presentationRevision
		return filter.shownTransfers(in: transfers, isSender: \.isSender)
	}

	var selectedTransfers: [FileTransferController] {
		transfers.filter { selection.contains($0.uniqueIdentifier) }
	}

	var stoppedTransfers: [FileTransferController] {
		transfers.filter { Self.stoppedStatuses.contains($0.transferStatus) }
	}

	var activeTransfers: [FileTransferController] {
		transfers.filter { [.receiving, .sending].contains($0.transferStatus) }
	}

	var receiverCount: Int {
		transfers.count { $0.isSender == false }
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
			return selected.contains { [.stopped, .recoverableError].contains($0.transferStatus) }
		case .stop:
			return selected.contains { Self.activeOrPendingStatuses.contains($0.transferStatus) }
		case .remove:
			return true
		case .open, .reveal:
			return selected.contains(where: Self.hasLocalFile)
		case .preview:
			return selected.allSatisfy(Self.hasLocalFile)
		}
	}

	func selectedFileURLs(for identifiers: Set<String>? = nil) -> [URL] {
		transfers(with: identifiers ?? selection)
			.filter(Self.hasLocalFile)
			.compactMap(\.fileURL)
	}

	var previewItems: [URL] {
		selectedFileURLs()
	}

	func presentPreview() {
		previewSelection = previewItems.first
	}

	func selectionDidChange() {
		guard previewSelection != nil else { return }
		let items = previewItems
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

	private static func hasLocalFile(_ transfer: FileTransferController) -> Bool {
		if transfer.isSender == false, transfer.transferStatus != .complete {
			return false
		}

		guard let filePath = transfer.filePath else { return false }
		return FileManager.default.fileExists(atPath: filePath)
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
	let status: String
	let progress: Progress

	init(transfer: FileTransferController) {
		filename = transfer.filename
		totalSize = Int64(clamping: transfer.totalFilesize).textualPaddedByteCountDescription
		progress = switch transfer.transferStatus {
		case .connecting:
			.indeterminate
		case .receiving, .sending:
			.determinate(value: transfer.processedFilesize, total: transfer.totalFilesize)
		default:
			.hidden
		}

		if [.fatalError, .recoverableError].contains(transfer.transferStatus) {
			status = transfer.errorMessageDescription ?? ""
		} else if [.sending, .receiving].contains(transfer.transferStatus) {
			status = Self.activeStatus(for: transfer, totalSize: totalSize)
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
		totalSize: String
	) -> String {
		let currentSpeed = averageSpeed(transfer.speedRecords)
		let processedSize = Int64(clamping: transfer.processedFilesize).textualPaddedByteCountDescription
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

	private static func averageSpeed(_ records: [NSNumber]) -> UInt64 {
		guard records.isEmpty == false else { return 0 }
		var total: UInt64 = 0
		for record in records {
			let (sum, overflow) = total.addingReportingOverflow(record.uint64Value)
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
