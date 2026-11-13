// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The public channel list a server sends in answer to `LIST`.

 Kept apart from `ServerSessionPresenting` because the application's scenes own the list
 window, not the main window. The protocol layer reports the listing as it
 arrives and never creates a list of its own: a reply for a list nobody has
 open is dropped by the receiver, which is what keeps a late `RPL_LIST` from
 reopening a closed window or asking the server again. */
@MainActor
protocol ChannelListPresenting: AnyObject {
	/// Shows `session`'s channel list and asks the server for a fresh one.
	func openChannelList(for session: ServerSession)
	/// Closes `session`'s channel list, if one is open.
	func closeChannelList(for session: ServerSession)
	/// `RPL_LISTSTART`: the server is starting a listing over.
	func channelListDidStart(for session: ServerSession)
	/// One `RPL_LIST` row.
	func channelListDidReceive(channelNamed name: String, memberCount: UInt, topic: String?, for session: ServerSession)
	/// `RPL_LISTEND`, or a reply saying the listing is not coming.
	func channelListDidFinish(for session: ServerSession)
}
