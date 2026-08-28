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

public typealias TrustDecisionHandler = (Bool) -> Void
public typealias TrustPanelCompletion = (SecTrust, Bool, Any?) -> Void

@objc(RCMTrustPanel)
public final class TrustPanelPresenter: NSObject, @unchecked Sendable {
	@objc(presentTrustPanelInWindow:body:title:defaultButton:alternateButton:trustRef:completionBlock:)
	public static func present(
		in window: NSWindow?,
		body: String,
		title: String,
		defaultButton: String,
		alternateButton: String?,
		trust: SecTrust,
		completion: @escaping TrustPanelCompletion
	) -> SFCertificateTrustPanel {
		present(
			in: window,
			body: body,
			title: title,
			defaultButton: defaultButton,
			alternateButton: alternateButton,
			trust: trust,
			completion: completion,
			context: nil
		)
	}

	@objc(presentTrustPanelInWindow:body:title:defaultButton:alternateButton:trustRef:completionBlock:contextInfo:)
	public static func present(
		in window: NSWindow?,
		body: String,
		title: String,
		defaultButton: String,
		alternateButton: String?,
		trust: SecTrust,
		completion: @escaping TrustPanelCompletion,
		context: Any?
	) -> SFCertificateTrustPanel {
		let input = UnsafeTransfer(value: (
			window,
			body,
			title,
			defaultButton,
			alternateButton,
			trust,
			completion,
			context
		))
		return performSynchronouslyOnMain {
			let (window, body, title, defaultButton, alternateButton, trust, completion, context) = input.value
			let callback = TrustPanelContext(
				trust: trust,
				completion: completion,
				context: context
			)
			let callbackPointer = Unmanaged.passRetained(callback).toOpaque()
			let panel = SFCertificateTrustPanel()
			panel.setDefaultButtonTitle(defaultButton)
			panel.setAlternateButtonTitle(alternateButton)
			panel.setInformativeText(body)
			panel.beginSheet(
				for: window,
				modalDelegate: self,
				didEnd: #selector(trustPanelDidEnd(_:returnCode:contextInfo:)),
				contextInfo: callbackPointer,
				trust: trust,
				message: title
			)
			return panel
		}
	}

	@objc private static func trustPanelDidEnd(
		_: NSWindow,
		returnCode: Int,
		contextInfo: UnsafeMutableRawPointer
	) {
		let context = Unmanaged<TrustPanelContext>.fromOpaque(contextInfo).takeRetainedValue()
		context.completion(context.trust, returnCode == NSApplication.ModalResponse.OK.rawValue, context.context)
	}
}

private final class TrustPanelContext: NSObject {
	/* SecTrust is ARC-managed in Swift; holding it strongly keeps the retain balanced. */
	let trust: SecTrust
	let completion: TrustPanelCompletion
	let context: Any?

	init(trust: SecTrust, completion: @escaping TrustPanelCompletion, context: Any?) {
		self.trust = trust
		self.completion = completion
		self.context = context
	}
}

private func performSynchronouslyOnMain<Result>(_ work: @escaping @MainActor () -> Result) -> Result {
	let workBox = UnsafeTransfer(value: work)
	let resultBox = UnsafeTransfer<Result?>(value: nil)
	if Thread.isMainThread {
		MainActor.assumeIsolated { resultBox.value = workBox.value() }
	} else {
		DispatchQueue.main.sync {
			MainActor.assumeIsolated { resultBox.value = workBox.value() }
		}
	}
	return resultBox.value!
}

private final class UnsafeTransfer<Value>: @unchecked Sendable {
	var value: Value
	init(value: Value) {
		self.value = value
	}
}
