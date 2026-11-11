// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/** Where a parsed `DCC` request ends up: a transfer in the file-transfer
 feature, a notification and a line in the transcript. */
extension ServerSession {
	/// The feature that owns this session's file transfers, resolved the same
	/// way the session resolves its other presenters. `nil` when there is no
	/// one to take a transfer — tests, teardown — which is what makes a session
	/// constructible without the file-transfer window.
	var fileTransfers: (any FileTransferPresenting)? {
		environment.services.fileTransfers
	}

	func notifyFileTransfer(
		_ type: UserNotificationEvent,
		nickname: String,
		filename: String,
		filesize totalFilesize: UInt64,
		requestIdentifier identifier: String
	) {
		let description = type.fileTransferBody(filename: filename, byteCount: totalFilesize)

		notifyEvent(
			type,
			lineType: .undefined,
			target: nil,
			nickname: nickname,
			text: description,
			/* The connection is named so the notification groups with the rest
				of its connection's, and so the Accept and Decline it offers can
				find the transfer they belong to. */
			userInfo: UserNotificationPayload(
				sessionIdentifier: uniqueIdentifier,
				fileTransferIdentifier: identifier,
				fileTransferEventRawValue: Int(type.rawValue)
			)
		)
	}

	func receivedDCCQuery(_ message: Message, text: String, ignoreInfo: AddressBookEntry?) {
		guard isLoggedIn, ignoreInfo?.ignoreFileTransferRequests != true,
		      let target = message.params.first, nicknameIsMyself(target),
		      let sender = message.senderNickname
		else { return }
		let uppercased = text.uppercased()
		if uppercased.hasPrefix("CHAT ") || uppercased.hasPrefix("SCHAT ") {
			receivedDCCChatQuery(sender, text: text)
			return
		}
		guard let request = DCCFileTransferRequestParser.parse(text) else {
			printInvalidDCCRequest(from: sender)
			return
		}
		processFileTransferRequest(request, sender: sender)
	}

	/// Counts an unsolicited offer from `sender` against the throttle, and says
	/// whether it may be taken.
	func admitsDCCOffer(from sender: String) -> Bool {
		guard dccOfferThrottle.recordOffer(from: supportInfo.casefoldString(sender), at: Date()) else {
			DirectConnectionLog.transfer.notice("Dropped a DCC offer past the offer throttle")
			return false
		}
		return true
	}

	/** Whether `nickname` is a person this user has told the address book to
	 track, and the person using the nickname right now is that person.

	 A nickname is not an identity: anyone can take one, including right after
	 its owner leaves. A tracking entry for the nickname is therefore not
	 enough. The sender must also be shown to be the person the entry names,
	 either by the services account the server reports for them or by the
	 `user@host` the entry itself pins. An offer from anyone else is still
	 listed for the user to accept, but it does not download on its own,
	 however the automatic download is set. */
	func isKnownFileTransferPeer(_ nickname: String) -> Bool {
		guard let entry = findUserTrackingAddressBookEntry(forNickname: nickname) else {
			return false
		}
		let sender = findUser(nickname)

		return FileTransferPeerTrust.isTrusted(
			senderHostmask: sender?.hostmask,
			senderAccount: sender?.account,
			trackedNickname: nickname,
			entryHostmask: entry.hostmask,
			caseMapping: supportInfo.caseMapping
		)
	}

	func receivedDCCSend(
		_ nickname: String,
		filename: String,
		address: String,
		port: UInt16,
		filesize totalFilesize: UInt64,
		token transferToken: String?
	) {
		guard admitsDCCOffer(from: nickname) else { return }
		print(
			String(localized: .IRC.receivedFileTransferRequest(nickname, filename, LocalizedByteCount.formatted(totalFilesize))),
			by: nil,
			in: nil,
			as: .dccFileTransfer, command: ChatLineFormat.defaultCommand
		)
		guard environment.settings.fileTransferRequestReplyAction != .ignore, let fileTransfers, let identifier = fileTransfers.addReceiver(
			for: self, nickname: nickname, address: address, port: port,
			filename: filename, filesize: totalFilesize, token: transferToken,
			peerIsKnown: isKnownFileTransferPeer(nickname)
		)
		else { return }
		notifyFileTransfer(
			.fileTransferReceiveRequested,
			nickname: nickname,
			filename: filename,
			filesize: totalFilesize,
			requestIdentifier: identifier
		)
	}

	func sendFileResume(
		_ nickname: String, port: UInt16, filename: String, filesize: UInt64, token: String?
	) {
		sendCTCPQuery(
			nickname,
			command: DCCCommand.resume.ctcpCommand,
			text: DCCFileTransferRequestParser.transferArguments(
				filename: filename, port: port, position: filesize, token: token
			)
		)
	}

	func sendFileResumeAccept(
		_ nickname: String, port: UInt16, filename: String, filesize: UInt64, token: String?
	) {
		sendCTCPQuery(
			nickname,
			command: DCCCommand.accept.ctcpCommand,
			text: DCCFileTransferRequestParser.transferArguments(
				filename: filename, port: port, position: filesize, token: token
			)
		)
	}

	func sendFile(
		_ nickname: String, port: UInt16, filename: String, filesize: UInt64, token: String?
	) {
		guard let address = DCCTransferAddress else { return }
		let arguments = DCCFileTransferRequestParser.sendArguments(
			filename: filename, address: address, port: port, filesize: filesize, token: token
		)
		sendCTCPQuery(nickname, command: DCCCommand.send.ctcpCommand, text: arguments)
		print(
			String(localized: .IRC.tryingFileTransfer(nickname, filename, LocalizedByteCount.formatted(filesize))),
			by: nil,
			in: nil,
			as: .dccFileTransfer, command: ChatLineFormat.defaultCommand
		)
	}

	var DCCTransferAddress: String? {
		guard let fileTransfers, let address = fileTransfers.ipAddress else { return nil }
		return DCCFormattedAddress(address)
	}

	func DCCFormattedAddress(_ address: String) -> String? {
		let formattedAddress = DCCWireFormat.wireAddress(address)
		if formattedAddress == nil {
			DirectConnectionLog.transfer.error("The configured file-transfer address is invalid")
		}
		return formattedAddress
	}

	private func processFileTransferRequest(_ request: DCCFileTransferRequest, sender: String) {
		switch request {
		case let .send(filename, _, _, _, _, .secure):
			/* Glasstual does not open secure transfers yet. An SSEND is declined
			 before anything else is read from it, so its token cannot answer a
			 plain offer of ours either. Each decline is a line in front of the
			 user, so a flood of them is throttled like any other offer. */
			guard admitsDCCOffer(from: sender) else { return }
			print(String(localized: .IRC.declinedSecureFileTransferOffer(sender, filename)), by: nil, in: nil,
			      as: .dccFileTransfer, command: ChatLineFormat.defaultCommand)
		case let .unsupported(verb):
			guard admitsDCCOffer(from: sender) else { return }
			print(String(localized: .IRC.declinedUnsupportedDccOffer(sender, verb)), by: nil, in: nil,
			      as: .dccFileTransfer, command: ChatLineFormat.defaultCommand)
		case let .send(filename, address, port, filesize, token, .plain):
			/* An active offer decides which host the session dials, so a peer
			 must not be able to point it at loopback or a private network. A
			 passive one — port zero — is dialled by the peer instead, and a
			 peer behind NAT names the private address it knows itself by. */
			guard port == 0 || DCCWireFormat.isDialableAddress(address) else {
				DirectConnectionLog.transfer.error("Refused a DCC SEND offer for a non-routable address")
				printInvalidDCCRequest(from: sender)
				return
			}
			guard let token else {
				receivedDCCSend(sender, filename: filename, address: address, port: port, filesize: filesize, token: nil)
				return
			}
			if port == 0 {
				/* A passive offer naming a token one of our own offers is already
				 waiting on is not an answer to it: ours is the one that asked. */
				guard fileTransfers?.sentOfferExists(
					withToken: token, on: self, peerNickname: sender, filename: filename
				) != true else {
					printInvalidDCCRequest(from: sender)
					return
				}
				receivedDCCSend(
					sender, filename: filename, address: address, port: port,
					filesize: filesize, token: token
				)
				return
			}
			guard fileTransfers?.sentOfferAccepted(
				withToken: token, on: self, peerNickname: sender, filename: filename,
				address: address, port: port, filesize: filesize
			) == true else {
				printInvalidDCCRequest(from: sender)
				return
			}
		case let .resume(filename, port, position, token):
			guard fileTransfers?.resumeRequested(
				at: position, on: self, peerNickname: sender, filename: filename, port: port, token: token
			) == true else {
				printInvalidDCCRequest(from: sender)
				return
			}
		case let .accept(filename, port, position, token):
			guard fileTransfers?.resumeAccepted(
				at: position, on: self, peerNickname: sender, filename: filename, port: port, token: token
			) == true else {
				printInvalidDCCRequest(from: sender)
				return
			}
		}
	}

	private func printInvalidDCCRequest(from sender: String) {
		DirectConnectionLog.transfer.error("Rejected an invalid DCC file-transfer request from \(sender, privacy: .private(mask: .hash))")
		print(String(localized: .IRC.glasstualHasReceivedADccRequest(sender)), by: nil, in: nil,
		      as: .dccFileTransfer, command: ChatLineFormat.defaultCommand)
	}
}
