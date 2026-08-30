/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit

private let transferCellViewIdentifier = NSUserInterfaceItemIdentifier("GroupView")

public extension FileTransferDialog {
	/// Builds the table's data source.
	///
	/// The cell used to come from the delegate's `tableView(_:viewFor:row:)`,
	/// which a diffable data source never calls, and its `objectValue` came from
	/// the array controller's `content` binding. Both are this closure's job
	/// now. `tableView(_:didAdd:forRow:)` still fires, and still fires after
	/// this has run, so the initial fill-in stays where it was.
	internal func makeTransferDataSource() -> FileTransferDataSource {
		FileTransferDataSource(tableView: fileTransferTable) { [weak self] tableView, _, _, transferID in
			let view = tableView.makeView(withIdentifier: transferCellViewIdentifier, owner: self)

			guard let cell = view as? FileTransferDialogTableCell else {
				return view ?? NSView()
			}

			guard let transfer = self?.fileTransfer(withUniqueIdentifier: transferID) else {
				return cell
			}

			cell.objectValue = transfer

			/* The transfer pushes progress straight at its cell rather than
			 through the table, so it is handed the way back. */
			transfer.transferTableCell = cell

			return cell
		}
	}

	/// Hands the table the transfers the toolbar is showing.
	internal func applyFileTransfers() {
		guard let transferDataSource else {
			return
		}

		/* Applying a snapshot clears the selection, which is held by row, so the
		 transfers holding it are remembered and looked up again afterwards. */
		let selected = fileTransferTable.selectedRowIndexes.compactMap {
			transferDataSource.itemIdentifier(forRow: $0)
		}

		var snapshot = NSDiffableDataSourceSnapshot<FileTransferSection, String>()
		snapshot.appendSections([.transfers])
		snapshot.appendItems(arrangedFileTransfers.map(\.uniqueIdentifier), toSection: .transfers)
		transferDataSource.apply(snapshot, animatingDifferences: false)

		guard selected.isEmpty == false else {
			return
		}

		let rows = IndexSet(selected.compactMap { transferDataSource.row(forItemIdentifier: $0) })

		if rows != fileTransferTable.selectedRowIndexes {
			fileTransferTable.selectRowIndexes(rows, byExtendingSelection: false)
		}
	}

	func tableView(_ tableView: NSTableView, didAdd _: NSTableRowView, forRow row: Int) {
		let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
			as? FileTransferDialogTableCell
		cell?.prepareInitialState()
	}

	func tableViewSelectionDidChange(_: Notification) {
		reloadQuickLookPanel()
	}

	@IBAction private func navigationSelectionDidChange(_: Any?) {
		applyFileTransfers()
	}

	/// Which transfers the toolbar is asking for. `.all` until the nib has
	/// connected the control.
	internal var navigationSelection: FileTransferSelection {
		guard let navigationControl else {
			return .all
		}

		return FileTransferSelection(rawValue: UInt(navigationControl.selectedSegment)) ?? .all
	}
}
