// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What the connection asks of the transfer list on the strength of a `DCC`
 request, and which listed transfer each request is about.

 The connection has only what the request said — a nickname, a port, a filename,
 a token — so working out which row it belongs to, and whether that row is in a
 state to answer, is the feature's half of the seam. Nothing here hands a
 transfer back: each answer is whether the request was acted on, which is what
 decides if the connection prints it as invalid instead. */
extension FileTransferStore: FileTransferPresenting {
	func sentOfferExists(withToken token: String, on session: ServerSession, peerNickname: String, filename: String) -> Bool {
		fileTransferSender(
			matchingToken: token, session: session, peerNickname: peerNickname, filename: filename
		) != nil
	}

	func sentOfferAccepted(
		withToken token: String,
		on session: ServerSession,
		peerNickname: String,
		filename: String,
		address: String,
		port: UInt16,
		filesize: UInt64
	) -> Bool {
		guard let transfer = fileTransferSender(
			matchingToken: token, session: session, peerNickname: peerNickname, filename: filename
		),
			transfer.transferStatus == .waitingForReceiverToAccept,
			transfer.totalFilesize == filesize
		else {
			return false
		}

		transfer.didReceiveSendRequest(address, hostPort: port)

		return true
	}

	func resumeRequested(
		at position: UInt64,
		on session: ServerSession,
		peerNickname: String,
		filename: String,
		port: UInt16,
		token: String?
	) -> Bool {
		guard let transfer = fileTransfer(
			matchingPort: port, token: token, session: session,
			peerNickname: peerNickname, filename: filename, isSender: true
		),
			transfer.transferStatus == .waitingForReceiverToAccept
			|| transfer.transferStatus == .isListeningAsSender
		else {
			return false
		}

		transfer.didReceiveResumeRequest(position)

		return true
	}

	func resumeAccepted(
		at position: UInt64,
		on session: ServerSession,
		peerNickname: String,
		filename: String,
		port: UInt16,
		token: String?
	) -> Bool {
		guard let transfer = fileTransfer(
			matchingPort: port, token: token, session: session,
			peerNickname: peerNickname, filename: filename, isSender: false
		),
			transfer.transferStatus == .waitingForResumeAccept
		else {
			return false
		}

		transfer.didReceiveResumeAccept(position)

		return true
	}

	/// The transfer a `RESUME` or `ACCEPT` is about. A reverse transfer is named
	/// by its token and carries no port; a plain one by the port it negotiated. A
	/// request that names both, or neither, names nothing.
	private func fileTransfer(
		matchingPort port: UInt16,
		token: String?,
		session: ServerSession,
		peerNickname: String,
		filename: String,
		isSender: Bool
	) -> FileTransfer? {
		if let token, port == 0 {
			return fileTransfer(
				matchingToken: token, session: session, peerNickname: peerNickname,
				filename: filename, isSender: isSender
			)
		}
		if token == nil, port > 0 {
			return fileTransfer(
				matchingPort: port, session: session, peerNickname: peerNickname,
				filename: filename, isSender: isSender
			)
		}
		return nil
	}
}

// MARK: - Which listed transfer a request is about

extension FileTransferStore {
	/// Locates the transfer a DCC `RESUME`/`ACCEPT` refers to.
	///
	/// A port on its own identifies nothing: it is unique to neither a network
	/// nor a peer, so matching on it alone lets any user on any connected
	/// network move the resume offset of somebody else's transfer. The session,
	/// the peer nickname and the filename all have to agree.
	func fileTransfer(
		matchingPort port: UInt16,
		session: ServerSession,
		peerNickname: String,
		filename: String,
		isSender: Bool
	) -> FileTransfer? {
		model.transfers.first {
			$0.hostPort == port && !$0.isReversed && $0.isSender == isSender
				&& Self.transfer($0, belongsTo: session, peerNickname: peerNickname, filename: filename)
		}
	}

	static func transfer(
		_ transfer: FileTransfer,
		belongsTo session: ServerSession,
		peerNickname: String,
		filename: String
	) -> Bool {
		let ourPeer = session.supportInfo.casefoldString(transfer.peerNickname)
		let theirPeer = session.supportInfo.casefoldString(peerNickname)

		guard transfer.sessionId == session.uniqueIdentifier, ourPeer == theirPeer else {
			return false
		}

		/* The peer echoes back the name we sent it, which crossed the wire in
		 its sanitised form, so compare the sanitised forms. */
		return transfer.wireFilename == filename
	}

	func fileTransfer(withUniqueIdentifier identifier: String) -> FileTransfer? {
		model.transfers.first { $0.uniqueIdentifier == identifier }
	}

	func fileTransferExists(withToken transferToken: String) -> Bool {
		model.transfers.contains { $0.transferToken == transferToken }
	}

	func fileTransferSender(
		matchingToken transferToken: String,
		session: ServerSession,
		peerNickname: String,
		filename: String
	) -> FileTransfer? {
		model.transfers.first {
			$0.transferToken == transferToken && $0.isSender
				&& Self.transfer($0, belongsTo: session, peerNickname: peerNickname, filename: filename)
		}
	}

	func fileTransfer(
		matchingToken token: String,
		session: ServerSession,
		peerNickname: String,
		filename: String,
		isSender: Bool
	) -> FileTransfer? {
		model.transfers.first {
			$0.isReversed && $0.transferToken == token && $0.isSender == isSender
				&& Self.transfer($0, belongsTo: session, peerNickname: peerNickname, filename: filename)
		}
	}
}
