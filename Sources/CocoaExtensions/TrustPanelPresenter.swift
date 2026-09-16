/* *********************************************************************
 *
 *            Copyright (c) 2024 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
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
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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
import Security
import SecurityInterface

/** `@Sendable` because the connection host calls this from its own XPC queue
 while the answer is decided on the main actor, and the closure is what carries
 the decision back across. */
public typealias TrustDecisionHandler = @Sendable (Bool) -> Void

/// One showing of the system's certificate trust sheet.
///
/// The presenter holds itself until the sheet ends, so a caller that only wants
/// to show a certificate can drop the result. A caller that may have to take
/// the sheet down again keeps it and calls ``dismiss()``.
///
/// Main actor throughout: it drives an AppKit sheet, and every caller is
/// already there.
@MainActor
public final class TrustPanelPresenter: NSObject {
	/// Puts the trust sheet for `trust` in front of the user, on `window` when
	/// there is one. `completion` is called with what the user answered, and not
	/// at all when the sheet is dismissed by ``dismiss()``.
	@discardableResult
	public static func present(
		in window: NSWindow?,
		body: String,
		title: String,
		defaultButton: String,
		alternateButton: String?,
		trust: SecTrust,
		completion: ((Bool) -> Void)? = nil
	) -> TrustPanelPresenter {
		let presenter = TrustPanelPresenter(trust: trust, completion: completion)
		presenter.begin(
			in: window,
			body: body,
			title: title,
			defaultButton: defaultButton,
			alternateButton: alternateButton
		)
		return presenter
	}

	/// Takes the sheet down without answering it.
	public func dismiss() {
		completion = nil
		let panel = panel
		finish()

		if let parent = panel.sheetParent {
			parent.endSheet(panel, returnCode: .cancel)
			return
		}

		if NSApp.modalWindow === panel {
			NSApp.stopModal(withCode: .cancel)
			return
		}

		panel.orderOut(nil)
	}

	/* SecTrust is ARC-managed in Swift; holding it strongly keeps the retain
	 balanced. */
	private let trust: SecTrust
	private let panel = SFCertificateTrustPanel()
	private var completion: ((Bool) -> Void)?
	/** What keeps the presenter alive while the sheet is up.

	 `didEnd` is not the only way a sheet goes away -- a caller that dismisses it
	 never reaches the selector -- so both exits release this, and nothing else
	 has to hold the presenter for it to work. */
	private var whileOnScreen: TrustPanelPresenter?

	private init(trust: SecTrust, completion: ((Bool) -> Void)?) {
		self.trust = trust
		self.completion = completion
		super.init()
		whileOnScreen = self
	}

	private func begin(
		in window: NSWindow?,
		body: String,
		title: String,
		defaultButton: String,
		alternateButton: String?
	) {
		panel.setDefaultButtonTitle(defaultButton)
		panel.setAlternateButtonTitle(alternateButton)
		panel.setInformativeText(body)
		panel.beginSheet(
			for: window,
			modalDelegate: self,
			didEnd: #selector(trustPanelDidEnd(_:returnCode:contextInfo:)),
			contextInfo: nil,
			trust: trust,
			message: title
		)
	}

	@objc private func trustPanelDidEnd(
		_: NSWindow,
		returnCode: Int,
		contextInfo _: UnsafeMutableRawPointer?
	) {
		let completion = completion
		finish()
		completion?(returnCode == NSApplication.ModalResponse.OK.rawValue)
	}

	private func finish() {
		completion = nil
		whileOnScreen = nil
	}
}
