// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

/// UI access is independent of the descriptor used for transfer/retry I/O.
struct FileTransferLocalFile {
	let url: URL
	let accessURL: URL

	func withAccess<Value>(_ operation: (URL) throws -> Value) rethrows -> Value {
		let lease = FileTransferAccessLease(url: accessURL)
		return try withExtendedLifetime(lease) { try operation(url) }
	}
}

/** The access the transfer window is holding on behalf of something it handed a
 file to.

 Quick Look and the share sheet both read a downloaded file after the thing that
 offered it has gone, so neither can borrow the scope around a `withAccess`
 call the way Open and Reveal do. Both lifetimes live here, so the list model
 keeps no leases of its own and there is one place to read what is still open. */
@Observable
final class FileTransferFileAccess {
	/// The file Quick Look is showing, or nil when it is closed. Closing it ends
	/// the access the preview was given.
	var previewSelection: URL? {
		didSet {
			if previewSelection == nil {
				previewLeases.removeAll()
			}
		}
	}

	private var previewLeases: [FileTransferAccessLease] = []

	@ObservationIgnored private var shareLeases: [FileTransferAccessLease] = []

	/// Opens Quick Look on `files`, starting with the first.
	func presentPreview(of files: [FileTransferLocalFile]) {
		previewLeases = files.map { FileTransferAccessLease(url: $0.accessURL) }
		previewSelection = files.first?.url
	}

	/** Follows a changed selection while Quick Look is open.

	 The preview stays on the file it is showing when that file is still among
	 the selected ones, so narrowing a selection down to it does not restart the
	 preview; otherwise it moves to the first of the new files. */
	func previewSelectionChanged(to files: [FileTransferLocalFile]) {
		guard previewSelection != nil else { return }

		previewLeases = files.map { FileTransferAccessLease(url: $0.accessURL) }
		let items = files.map(\.url)
		if let previewSelection, items.contains(previewSelection) {
			return
		}
		previewSelection = items.first
	}

	/// The URLs a share of `files` puts in front of the user, with their access
	/// held for as long as the share can still read them.
	func share(_ files: [FileTransferLocalFile]) -> [URL] {
		shareLeases = files.map { FileTransferAccessLease(url: $0.accessURL) }
		return files.map(\.url)
	}

	/// Ends the access the last share was offered. Nothing can reach the rows the
	/// share came from once the window is gone.
	func releaseShareAccess() {
		shareLeases.removeAll()
	}
}
