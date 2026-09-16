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
import Foundation

extension TranscriptView {
	/** Prints the transcript as it stands, on paper.

	 `NSPrintOperation` paginates whatever view it is handed, and the one on
	 screen is the wrong one: its colours are already resolved for the reader's
	 appearance, so a dark theme prints a black page with pale text hidden in
	 it. A throw-away text view is laid out instead, against the theme's light
	 half, with the conversation, its network and the date at the head of every
	 page and the page number at the foot. */
	func printContent() {
		guard let window else { return }
		/* A copy of the shared settings: the running head belongs to this
		 operation, not to every print the application starts afterwards. */
		let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
		/* What makes AppKit draw the running head and foot: the head is the job
		 title beside the date, and the foot is the page number. */
		printInfo.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = true

		let printView = NSTextView(frame: NSRect(origin: .zero, size: printInfo.imageablePageBounds.size))
		printView.isEditable = false
		printView.isHorizontallyResizable = false
		printView.isVerticallyResizable = true
		printView.textContainer?.widthTracksTextView = true
		printView.textStorage?.setAttributedString(printableDocument())

		let operation = NSPrintOperation(view: printView, printInfo: printInfo)
		if printedDocumentTitle.isEmpty == false {
			operation.jobTitle = printedDocumentTitle
		}
		operation.showsPrintPanel = true
		operation.showsProgressPanel = true
		operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
	}

	/// The transcript rendered a second time against the light palette. The
	/// document on screen cannot be reused: its colours are already resolved.
	private func printableDocument() -> NSAttributedString {
		renderingForPrint {
			/* Before and after: the nickname colours this pass resolves are the
			 light ones, and the transcript on screen must not be handed them. */
			beginNicknameColorBatch()
			let paper = NSMutableAttributedString()
			for line in document.lines {
				paper.append(render(line))
			}
			beginNicknameColorBatch()
			return paper
		}
	}

	/// What the printer queue and the running head call this job: the
	/// conversation and the network it is on.
	private var printedDocumentTitle: String {
		let controller = viewController
		return [controller?.associatedChannel?.name, controller?.associatedClient?.networkNameAlt]
			.compactMap(\.self)
			.filter { $0.isEmpty == false }
			.joined(separator: " — ")
	}
}
