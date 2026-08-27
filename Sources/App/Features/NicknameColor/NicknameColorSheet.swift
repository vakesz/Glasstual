/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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
import SwiftUI

@objc(TDCNicknameColorSheetDelegate)
public protocol NicknameColorSheetDelegate: NSObjectProtocol {
	@objc(nicknameColorSheetOnOk:)
	func nicknameColorSheetOnOk(_ sender: NicknameColorSheet)

	@objc(nicknameColorSheetWillClose:)
	func nicknameColorSheetWillClose(_ sender: NicknameColorSheet)
}

@objc(TDCNicknameColorSheet)
@MainActor
public final class NicknameColorSheet: SheetBase, NSWindowDelegate {
	private static let contentSize = NSSize(width: 390, height: 112)

	private let nickname: String
	let model: NicknameColorModel

	@objc(initWithNickname:)
	public init(nickname: String) {
		self.nickname = nickname
		model = NicknameColorModel(
			nickname: nickname,
			overrideColor: UserNicknameColorStyleGenerator.nicknameColorStyleOverride(forKey: nickname)
		)

		super.init(window: nil)
		installSheet()
	}

	private func installSheet() {
		let content = NicknameColorContent.current
		let rootView = NicknameColorView(
			model: model,
			content: content,
			selectColor: { [weak self] color in
				self?.nicknameColorChanged(color)
			},
			setUsesDefaultColor: { [weak self] usesDefaultColor in
				self?.useDefaultColorToggled(usesDefaultColor)
			},
			save: { [weak self] in
				self?.ok(nil)
			},
			cancel: { [weak self] in
				self?.cancel(nil)
			}
		)
		let hostedSheet = NSWindow(
			contentRect: NSRect(origin: .zero, size: Self.contentSize),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)

		hostedSheet.contentView = NSHostingView(rootView: rootView)
		hostedSheet.contentMinSize = Self.contentSize
		hostedSheet.contentMaxSize = Self.contentSize
		hostedSheet.delegate = self
		hostedSheet.isReleasedWhenClosed = false
		hostedSheet.isRestorable = false
		hostedSheet.tabbingMode = .disallowed
		hostedSheet.title = content.windowTitle
		hostedSheet.titleVisibility = .hidden
		hostedSheet.titlebarAppearsTransparent = true
		hostedSheet.titlebarSeparatorStyle = .none
		sheet = hostedSheet
	}

	@objc public func start() {
		startSheet()
	}

	@IBAction override public func ok(_ sender: Any?) {
		UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(
			model.colorForPersistence,
			forKey: nickname
		)

		(delegate as? NicknameColorSheetDelegate)?.nicknameColorSheetOnOk(self)

		super.ok(sender)
	}

	@IBAction public func useDefaultColorToggled(_ sender: Any?) {
		let usesDefaultColor: Bool = if let button = sender as? NSButton {
			button.state == .on
		} else if let value = sender as? Bool {
			value
		} else {
			!model.usesDefaultColor
		}

		model.setUsesDefaultColor(usesDefaultColor)

		if usesDefaultColor, NSColorPanel.sharedColorPanelExists {
			NSColorPanel.shared.close()
		}
	}

	@IBAction public func nicknameColorChanged(_ sender: Any?) {
		if let colorWell = sender as? NSColorWell {
			model.selectColor(colorWell.color)
		} else if let color = sender as? NSColor {
			model.selectColor(color)
		} else {
			model.markCustomColorSelected()
		}
	}

	@objc public func windowWillClose(_: Notification) {
		(delegate as? NicknameColorSheetDelegate)?.nicknameColorSheetWillClose(self)
	}
}
