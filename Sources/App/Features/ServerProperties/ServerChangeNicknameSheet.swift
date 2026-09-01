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

import Foundation
import SwiftUI

@MainActor
public protocol ServerChangeNicknameSheetDelegate: NSObjectProtocol {
	func serverChangeNicknameSheet(_ sender: ServerChangeNicknameSheet, didInputNickname nickname: String)

	func serverChangeNicknameSheetWillClose(_ sender: ServerChangeNicknameSheet)
}

@MainActor
public final class ServerChangeNicknameSheet: MainWindowSheetSession, ClientScoped {
	public private(set) var client: IRCClient?
	public private(set) var clientId: String?

	private let content: ServerNicknameChangeContent
	private let model: ServerNicknameChangeModel

	public init(client: IRCClient) {
		let currentNickname = client.userNickname

		self.client = client
		clientId = client.uniqueIdentifier
		content = .current
		model = ServerNicknameChangeModel(currentNickname: currentNickname) { candidate in
			if candidate.isEmpty {
				return ApplicationStrings.requiredField
			}

			guard (candidate as NSString).isHostmaskNickname(on: client) else {
				return CommonValidationStrings.invalidNickname
			}

			return nil
		}

		super.init(window: nil)
		installSheet()
	}

	private func installSheet() {
		let rootView = ServerNicknameChangeView(
			model: model,
			content: content,
			submit: { [weak self] in
				self?.ok(nil)
			},
			cancel: { [weak self] in
				self?.cancel(nil)
			}
		)
		setContent(rootView)
	}

	public func start() {
		startSheet()
	}

	override public func ok(_ sender: Any?) {
		guard okOrError() else {
			return
		}

		(delegate as? ServerChangeNicknameSheetDelegate)?.serverChangeNicknameSheet(
			self,
			didInputNickname: model.normalizedNickname
		)

		super.ok(sender)
	}

	public func okOrError() -> Bool {
		model.validateForSubmission()
	}

	override public func sheetDidEnd(withReturnCode _: Int) {
		(delegate as? ServerChangeNicknameSheetDelegate)?.serverChangeNicknameSheetWillClose(self)
	}
}
