/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
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

final class ClientRequestedCommands: NSObject {
	private enum Command {
		case ison
		case who
	}

	private struct Request {
		let command: Command
		let responseIsHidden: Bool
		/// The nicknames an ISON asked about. One reply answers for these and
		/// nobody else.
		var nicknames: [String] = []
	}

	private var requests: [Request] = []

	func removeCommands() {
		requests.removeAll()
	}

	var visibleIsonRequest: Bool {
		responseIsVisible(for: .ison)
	}

	/// Records a hidden ISON asking about `nicknames`.
	func recordIsonRequestOpened(askingAbout nicknames: [String]) {
		requests.append(Request(command: .ison, responseIsHidden: true, nicknames: nicknames))
	}

	func recordIsonRequestOpenedAsVisible() {
		addRequest(for: .ison, responseIsHidden: false)
	}

	/** Closes the oldest ISON request and returns the nicknames it asked about.

	 A long list goes out as several ISON commands and each draws its own
	 `RPL_ISON`, so a reply says who is online among that one command's
	 nicknames. Read as the whole online set it signed off everyone the other
	 commands asked about, on every poll. Empty when no request was open. */
	@discardableResult
	func recordIsonRequestClosed() -> [String] {
		removeFirstRequest(for: .ison)?.nicknames ?? []
	}

	/// Whether an ISON is still waiting for its reply.
	var hasOpenIsonRequest: Bool {
		requests.contains { $0.command == .ison }
	}

	var visibleWhoRequest: Bool {
		responseIsVisible(for: .who)
	}

	func recordWhoRequestOpened() {
		addRequest(for: .who, responseIsHidden: true)
	}

	func recordWhoRequestOpenedAsVisible() {
		addRequest(for: .who, responseIsHidden: false)
	}

	func recordWhoRequestClosed() {
		removeFirstRequest(for: .who)
	}

	private func addRequest(for command: Command, responseIsHidden: Bool) {
		requests.append(Request(command: command, responseIsHidden: responseIsHidden))
	}

	@discardableResult
	private func removeFirstRequest(for command: Command) -> Request? {
		guard let index = requests.firstIndex(where: { $0.command == command }) else {
			return nil
		}

		return requests.remove(at: index)
	}

	private func responseIsVisible(for command: Command) -> Bool {
		guard let request = requests.first(where: { $0.command == command }) else {
			return false
		}

		return request.responseIsHidden == false
	}
}
