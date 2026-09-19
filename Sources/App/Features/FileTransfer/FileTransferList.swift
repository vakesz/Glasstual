// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Observation

/// Which transfer directions the window is showing.
enum FileTransferDirectionFilter: String, CaseIterable, Identifiable, Sendable {
	case all
	case sending
	case receiving

	var id: String {
		rawValue
	}

	func transfers<Transfer>(
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
	case downloadTo
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
	private var hasActivated = false
	private var hasExplicitReveal = false

	func reveal(_ identifier: String) {
		hasExplicitReveal = true
		filter = .all
		selection = [identifier]
	}

	/// Scene restoration is a launch default; a notification's explicit target
	/// and subsequent user edits take precedence for this model's lifetime.
	func activate(restoring savedFilter: FileTransferDirectionFilter) {
		guard !hasActivated else { return }
		hasActivated = true
		if !hasExplicitReveal {
			filter = savedFilter
		}
	}

	/// The access Quick Look and the share sheet are holding, which outlives the
	/// row menu that opened either one.
	let fileAccess = FileTransferFileAccess()

	var isChoosingDestination = false
	var filter = FileTransferDirectionFilter.all {
		didSet { retainVisibleSelection() }
	}

	var visibleTransfers: [FileTransfer] {
		filter.transfers(in: transfers, isSender: \.isSender)
	}

	var stoppedTransfers: [FileTransfer] {
		transfers.filter { $0.transferStatus.isRunning == false }
	}

	var activeTransfers: [FileTransfer] {
		transfers.filter(\.transferStatus.isActive)
	}

	/** How many downloads are actually in flight or still waiting to start.

	 Fresh offers have the stopped status until the user accepts them. They
	 must count too, or a peer can add unlimited unanswered offers. Completed
	 and failed rows stay in the list without spending the limit. */
	var receiverCount: Int {
		transfers.count {
			$0.isSender == false && ($0.transferStatus.isRunning || $0.transferStatus == .stopped)
		}
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
		case .downloadTo:
			return selected.contains { $0.isSender == false && $0.canStart && $0.path == nil }
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
			return String(localized: .FileTransfer.retryTransfer)
		}
		if startable.isEmpty == false, startable.allSatisfy({ $0.isSender == false && $0.transferStatus == .stopped }) {
			return String(localized: .FileTransfer.acceptTransfer)
		}
		return String(localized: .FileTransfer.startTransfer)
	}

	func selectedFileURLs(for identifiers: Set<String>? = nil) -> [URL] {
		selectedLocalFiles(for: identifiers).map(\.url)
	}

	func selectedLocalFiles(for identifiers: Set<String>? = nil) -> [FileTransferLocalFile] {
		transfers(with: identifiers ?? selection).compactMap { localFile(of: $0) }
	}

	/// The files a share of `identifiers` puts in front of the user.
	func shareableFileURLs(for identifiers: Set<String>) -> [URL] {
		fileAccess.share(selectedLocalFiles(for: identifiers))
	}

	var previewItems: [URL] {
		selectedFileURLs()
	}

	func presentPreview() {
		fileAccess.presentPreview(of: selectedLocalFiles())
	}

	func selectionDidChange() {
		fileAccess.previewSelectionChanged(to: selectedLocalFiles())
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
