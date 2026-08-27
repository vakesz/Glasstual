/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2015 - 2026 Codeux Software, LLC & respective contributors.
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

@MainActor
enum ChatFilterAlert {
	static func confirm(
		message: String,
		title: String,
		defaultButton: String,
		alternateButton: String
	) -> Bool {
		present(
			message: message,
			title: title,
			defaultButton: defaultButton,
			alternateButton: alternateButton
		) == .alertFirstButtonReturn
	}

	static func inform(message: String, title: String, dismissButton: String) {
		_ = present(
			message: message,
			title: title,
			defaultButton: dismissButton,
			alternateButton: nil
		)
	}

	private static func present(
		message: String,
		title: String,
		defaultButton: String,
		alternateButton: String?
	) -> NSApplication.ModalResponse {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.addButton(withTitle: defaultButton)
		if let alternateButton {
			alert.addButton(withTitle: alternateButton)
		}
		return alert.runModal()
	}
}

@objc(TPIChatFilterTableView)
@MainActor
final class ChatFilterTableView: NSTableView {
	override func menu(for event: NSEvent) -> NSMenu? {
		let rowBeneathMouse = row(at: convert(event.locationInWindow, from: nil))
		if rowBeneathMouse >= 0, selectedRowIndexes.contains(rowBeneathMouse) == false {
			selectRowIndexes(IndexSet(integer: rowBeneathMouse), byExtendingSelection: false)
		}

		return selectedRow < 0 ? nil : menu
	}
}
