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

public extension FileTransferDialog {
	func tableView(
		_ tableView: NSTableView,
		viewFor _: NSTableColumn?,
		row: Int
	) -> NSView? {
		guard let transfer = fileTransfer(atArrangedIndex: row),
		      let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("GroupView"), owner: self)
		      as? FileTransferDialogTableCell
		else {
			return nil
		}

		transfer.transferTableCell = view
		return view
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
		switch navigationSelection {
		case .sending:
			fileTransfersController.filterPredicate = NSPredicate(format: "isSender == YES")
		case .receiving:
			fileTransfersController.filterPredicate = NSPredicate(format: "isSender == NO")
		default:
			fileTransfersController.filterPredicate = nil
		}
	}

	private var navigationSelection: FileTransferSelection {
		FileTransferSelection(rawValue: UInt(navigationControl.selectedSegment)) ?? .all
	}
}
