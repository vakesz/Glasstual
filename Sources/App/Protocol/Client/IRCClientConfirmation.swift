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

extension IRCClient {
	/// Keeps a pending user decision in this session. A delayed answer cannot
	/// act on a replacement connection, a removed channel or a cancelled task.
	func requestConfirmation(
		_ request: AlertRequest,
		isCurrent: @escaping @MainActor (IRCClient) -> Bool = { _ in true },
		perform action: @escaping @MainActor (IRCClient) -> Void
	) {
		guard let output else {
			if !isTerminating, isCurrent(self) {
				action(self)
			}
			return
		}
		let identifier = UUID()
		let session = startup.identifier
		let connection = socket?.uniqueIdentifier
		pendingConfirmationTasks[identifier] = Task { [weak self, weak output] in
			guard let output else {
				self?.pendingConfirmationTasks.removeValue(forKey: identifier)
				return
			}
			let accepted = await output.confirm(request)
			guard let self else { return }
			defer { pendingConfirmationTasks.removeValue(forKey: identifier) }
			guard accepted, !Task.isCancelled, !isTerminating,
			      startup.identifier == session, socket?.uniqueIdentifier == connection,
			      isCurrent(self) else { return }
			action(self)
		}
	}
}
