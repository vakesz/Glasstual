/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

nonisolated enum IRCDirectChatStrings {
	static var notConnected: String {
		String(localized: .IRC.directChatIsNotConnected)
	}

	static func fileCouldNotBeOffered(path: String) -> String {
		String(localized: .IRC.fileAtCouldNotBeOffered(path))
	}

	static func incomingRequest(sender: String) -> String {
		String(localized: .IRC.wantsToStartADirectChat(sender))
	}

	static func declined(sender: String) -> String {
		String(localized: .IRC.declinedDirectChatRequest(sender))
	}

	static func connecting(nickname: String, address: String, port: UInt16) -> String {
		String(localized: .IRC.connectingToForADirectChat(nickname, address, UInt(port)))
	}

	static func offering(to nickname: String) -> String {
		String(localized: .IRC.offeringADirectChat(nickname))
	}

	static func unprocessableRequest(sender: String) -> String {
		String(localized: .IRC.glasstualHasReceivedADccRequest(sender))
	}

	static func addressUnavailable(nickname: String) -> String {
		String(localized: .IRC.couldNotDetermineAnAddress(nickname))
	}

	static func waitingForConnection(nickname: String, port: UInt16) -> String {
		String(localized: .IRC.waitingForToConnectOnPort(nickname, UInt(port)))
	}

	static func established(nickname: String) -> String {
		String(localized: .IRC.directChatWithEstablished(nickname))
	}

	static func closed(nickname: String, error: String?) -> String {
		if let error {
			return String(localized: .IRC.directChatWithClosed(nickname, error))
		}

		return String(localized: .IRC.directChatDccChatWithClosed(nickname))
	}
}

nonisolated enum IRCFileTransferStrings {
	static func request(nickname: String, filename: String, byteCount: UInt64) -> String {
		String(localized: .IRC.receivedFileTransferRequest(nickname, filename, LocalizedByteCount.formatted(byteCount)))
	}

	static func attempt(nickname: String, filename: String, byteCount: UInt64) -> String {
		String(localized: .IRC.tryingFileTransfer(nickname, filename, LocalizedByteCount.formatted(byteCount)))
	}
}
