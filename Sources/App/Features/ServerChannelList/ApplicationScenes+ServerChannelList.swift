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

/** The channel-list window, as the protocol layer reports to it.

 `Protocol/` must not depend on feature presentation, so it speaks to
 ``ClientChannelListPresenting`` and the application's scenes answer. A reply
 only ever reaches a list that is already open: opening one is the single path
 that makes a session and asks the server for a listing. */
extension ApplicationScenes: ClientChannelListPresenting {
	func openChannelList(for client: IRCClient) {
		openServerChannelList(for: client)
	}

	func closeChannelList(for client: IRCClient) {
		closeServerChannelList(for: client.uniqueIdentifier)
	}

	func channelListDidStart(for client: IRCClient) {
		serverChannelList(for: client.uniqueIdentifier)?.receiveListStart()
	}

	func channelListDidReceive(channelNamed name: String, memberCount: UInt, topic: String?, for client: IRCClient) {
		serverChannelList(for: client.uniqueIdentifier)?.addChannel(name, count: memberCount, topic: topic)
	}

	func channelListDidFinish(for client: IRCClient) {
		serverChannelList(for: client.uniqueIdentifier)?.finishRefresh()
	}
}
