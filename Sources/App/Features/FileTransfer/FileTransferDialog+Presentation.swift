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
import CocoaExtensions
import QuickLookUI

extension FileTransferDialog {
	public func show(_ makeKeyWindow: Bool) {
		show(makeKeyWindow, restorePosition: true)
	}

	public func show(_ makeKeyWindow: Bool, restorePosition: Bool) {
		if makeKeyWindow {
			window.makeKeyAndOrderFront(nil)
		} else {
			window.orderFront(nil)
		}

		if restorePosition {
			window.ce_restoreState(for: .fileTransfers)
		}
	}

	func beginPreviewPanelControlOnMainActor(_ panel: QLPreviewPanel) {
		previewItems = model.selectedFileURLs()
		panel.dataSource = self
		panel.delegate = self
		panel.currentPreviewItemIndex = 0
	}

	func endPreviewPanelControlOnMainActor(_ panel: QLPreviewPanel) {
		guard panel.isVisible == false else { return }

		panel.dataSource = nil
		panel.delegate = nil
		previewItems = []
	}

	@MainActor public func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
		previewItems.count
	}

	@MainActor public func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
		guard previewItems.indices.contains(index) else { return nil }
		return previewItems[index] as NSURL
	}

	public func windowWillClose(_: Notification) {
		window.ce_saveState(for: .fileTransfers)

		guard QLPreviewPanel.sharedPreviewPanelExists(),
		      let panel = QLPreviewPanel.shared(),
		      panel.isVisible,
		      controlsPreviewPanel(panel)
		else {
			return
		}

		panel.orderOut(nil)
	}

	func controlsPreviewPanel(_ panel: QLPreviewPanel) -> Bool {
		Self.previewPanel(controlledBy: panel.currentController, is: window)
	}

	static func previewPanel(controlledBy controller: Any?, is window: NSWindow?) -> Bool {
		guard let window else { return false }
		return controller as AnyObject? === window
	}

	func openFiles(for identifiers: Set<String>) {
		model.selectedFileURLs(for: identifiers).forEach { NSWorkspace.shared.open($0) }
	}

	func revealFiles(for identifiers: Set<String>) {
		let urls = model.selectedFileURLs(for: identifiers)
		guard urls.isEmpty == false else { return }
		NSWorkspace.shared.activateFileViewerSelecting(urls)
	}

	func toggleQuickLookPanel() {
		guard model.selectedFileURLs().isEmpty == false,
		      let panel = QLPreviewPanel.shared()
		else { return }

		if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible, controlsPreviewPanel(panel) {
			panel.orderOut(nil)
			return
		}

		beginPreviewPanelControlOnMainActor(panel)
		panel.makeKeyAndOrderFront(nil)
	}

	func reloadQuickLookPanel() {
		guard QLPreviewPanel.sharedPreviewPanelExists(),
		      let panel = QLPreviewPanel.shared(),
		      controlsPreviewPanel(panel)
		else {
			return
		}

		previewItems = model.selectedFileURLs()
		panel.reloadData()
	}
}
