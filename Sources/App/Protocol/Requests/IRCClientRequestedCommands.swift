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

@objc(IRCClientRequestedCommands)
public final class ClientRequestedCommands: NSObject {
	private enum Command {
		case ison
		case who
	}

	private struct Request {
		let command: Command
		let responseIsHidden: Bool
	}

	private let lock = NSLock()
	private var requests: [Request] = []

	@objc public func removeCommands() {
		lock.withLock {
			requests.removeAll()
		}
	}

	@objc(inVisibleIsonRequest)
	public var visibleIsonRequest: Bool {
		responseIsVisible(for: .ison)
	}

	@objc public func recordIsonRequestOpened() {
		addRequest(for: .ison, responseIsHidden: true)
	}

	@objc public func recordIsonRequestOpenedAsVisible() {
		addRequest(for: .ison, responseIsHidden: false)
	}

	@objc public func recordIsonRequestClosed() {
		removeFirstRequest(for: .ison)
	}

	@objc(inVisibleWhoRequest)
	public var visibleWhoRequest: Bool {
		responseIsVisible(for: .who)
	}

	@objc public func recordWhoRequestOpened() {
		addRequest(for: .who, responseIsHidden: true)
	}

	@objc public func recordWhoRequestOpenedAsVisible() {
		addRequest(for: .who, responseIsHidden: false)
	}

	@objc public func recordWhoRequestClosed() {
		removeFirstRequest(for: .who)
	}

	private func addRequest(for command: Command, responseIsHidden: Bool) {
		lock.withLock {
			requests.append(Request(command: command, responseIsHidden: responseIsHidden))
		}
	}

	private func removeFirstRequest(for command: Command) {
		lock.withLock {
			guard let index = requests.firstIndex(where: { $0.command == command }) else {
				return
			}

			requests.remove(at: index)
		}
	}

	private func responseIsVisible(for command: Command) -> Bool {
		lock.withLock {
			guard let request = requests.first(where: { $0.command == command }) else {
				return false
			}

			return request.responseIsHidden == false
		}
	}
}
