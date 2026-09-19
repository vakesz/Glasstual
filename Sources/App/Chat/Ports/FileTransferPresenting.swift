// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What a parsed `DCC` request needs from the file-transfer feature.

 Everything above this is wire parsing that needs no feature at all, so this is
 the one seam the request path crosses: no transfer, list or window type is
 named under `Chat/DirectConnection` any more. Every member speaks in the terms
 the request arrived in — a nickname, a port, a filename, a token — and no
 transfer crosses it: the feature finds the transfer a request belongs to,
 decides whether it is one that transfer can act on, and answers whether it
 did. */
@MainActor
protocol FileTransferPresenting: AnyObject {
	/// The address this Mac's offers name, as far as it is already known.
	var ipAddress: String? { get }

	/** Works out the address this Mac's offers name, asking the address service
	 when it is not known yet.

	 `routerAddress` is the public address a port mapping reported, if it made
	 one. `nil` when there is no address to be had. */
	func lookUpIPAddress(routerAddress: String?) async -> String?

	/** Lists an inbound `DCC SEND`, and starts it when the settings say an offer
	 from a peer the user already knows downloads on its own.

	 The identifier a notification for the offer should name, or `nil` when the
	 offer was refused outright. */
	func addReceiver(
		for session: ServerSession,
		nickname: String,
		address: String,
		port: UInt16,
		filename: String,
		filesize: UInt64,
		token: String?,
		peerIsKnown: Bool
	) -> String?

	/// Offers `path` to `nickname`, reserving the file first. `completion`
	/// receives the transfer's identifier, or `nil` when it could not be offered.
	func offerSender(
		for session: ServerSession,
		nickname: String,
		path: String,
		autoOpen: Bool,
		accessURL: URL?,
		completion: @escaping (String?) -> Void
	)

	/// Whether an offer of this session's is already waiting on `token`.
	func sentOfferExists(withToken token: String, on session: ServerSession, peerNickname: String, filename: String) -> Bool

	/** `DCC SEND` answering a reverse offer of ours: the peer is listening at
	 `address`, and the offer it names dials it.

	 `false` when no offer of ours is waiting on that token, or the one it names
	 disagrees about the file, in which case the request is not one we sent for. */
	func sentOfferAccepted(
		withToken token: String,
		on session: ServerSession,
		peerNickname: String,
		filename: String,
		address: String,
		port: UInt16,
		filesize: UInt64
	) -> Bool

	/// `DCC RESUME`: the peer asks for the rest of a file we are sending, from
	/// `position`. `false` when no transfer of ours is in a state to answer it.
	func resumeRequested(
		at position: UInt64,
		on session: ServerSession,
		peerNickname: String,
		filename: String,
		port: UInt16,
		token: String?
	) -> Bool

	/// `DCC ACCEPT`: the peer agreed to the resume we asked for. `false` when no
	/// transfer of ours is waiting for that answer.
	func resumeAccepted(
		at position: UInt64,
		on session: ServerSession,
		peerNickname: String,
		filename: String,
		port: UInt16,
		token: String?
	) -> Bool
}
