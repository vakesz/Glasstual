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

enum IRCClientReachabilityPolicy {
	/// Whether losing reachability should tear the session down. Callers only
	/// ask once the connection is already known to be unreachable, so there is
	/// no reachability argument.
	static func shouldDisconnect(isLoggedIn: Bool, disconnectWhenUnreachable: Bool) -> Bool {
		isLoggedIn && disconnectWhenUnreachable
	}
}

@MainActor
public extension IRCClient {
	func clearCachedHighlights() {
		cachedHighlights = []
	}

	func cacheHighlight(in channel: IRCChannel, with logLine: LogLine) {
		guard environment.preferences.logHighlights else { return }

		let newEntry = HighlightLogEntry(
			lineLogged: logLine,
			clientId: uniqueIdentifier,
			channelId: channel.uniqueIdentifier
		)
		cachedHighlights.insert(newEntry, at: 0)

		guard let sheet = SharedApplication.sharedWindowController()
			.window(fromWindowList: "TDCServerHighlightListSheet") as? ServerHighlightListSheet,
			sheet.clientId == uniqueIdentifier,
			let firstEntry = cachedHighlights.first
		else { return }
		sheet.addEntry(firstEntry)
	}

	func noteReachabilityChanged(_ reachable: Bool) {
		guard reachable == false else { return }
		disconnectOnReachabilityChange()
	}

	func disconnectOnReachabilityChange() {
		guard IRCClientReachabilityPolicy.shouldDisconnect(
			isLoggedIn: isLoggedIn,
			disconnectWhenUnreachable: config.performDisconnectOnReachabilityChange
		) else { return }

		disconnectType = .reachabilityChange
		reconnectEnabled = true
		disconnect()
	}
}
