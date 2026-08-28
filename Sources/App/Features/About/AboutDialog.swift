/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
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
import SwiftUI

@objc(TDCAboutDialogDelegate)
@MainActor
public protocol AboutDialogDelegate: NSObjectProtocol {
	@objc(aboutDialogWillClose:)
	func aboutDialogWillClose(_ sender: AboutDialog)
}

@MainActor
@objc(TDCAboutDialog)
public final class AboutDialog: WindowBase, NSWindowDelegate, @unchecked Sendable {
	private static let contentSize = NSSize(width: 218, height: 244)

	private func makeWindow() -> NSWindow {
		let window = NSWindow(
			contentRect: NSRect(origin: .zero, size: Self.contentSize),
			styleMask: [.titled, .closable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		let applicationIcon = NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 98, height: 98))
		let rootView = AboutView(
			content: .current,
			applicationIcon: applicationIcon,
			openAcknowledgements: { [weak self] in
				self?.displayAcknowledgements(nil)
			},
			close: { [weak window] in
				window?.performClose(nil)
			}
		)

		window.contentViewController = NSHostingController(rootView: rootView)
		window.contentMinSize = Self.contentSize
		window.contentMaxSize = Self.contentSize
		window.delegate = self
		window.isReleasedWhenClosed = false
		window.isRestorable = false
		window.tabbingMode = .disallowed
		window.title = AboutContent.current.applicationName
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.titlebarSeparatorStyle = .none
		window.center()

		return window
	}

	@discardableResult
	func prepareWindow() -> NSWindow {
		if let window {
			return window
		}

		let hostedWindow = makeWindow()
		window = hostedWindow

		return hostedWindow
	}

	@objc override public func show() {
		MainActor.assumeIsolated {
			showOnMainActor()
		}
	}

	private func showOnMainActor() {
		let window = prepareWindow()
		window.ce_restoreState(for: Self.self)
		super.show()
	}

	@IBAction public func displayAcknowledgements(_ sender: Any?) {
		AppController.shared.menuController?.openAcknowledgements(sender)
	}

	@objc public func windowWillClose(_: Notification) {
		window.ce_saveState(for: Self.self)
		(delegate as? AboutDialogDelegate)?.aboutDialogWillClose(self)
	}
}
