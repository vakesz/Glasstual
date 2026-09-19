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
		if text.uppercased().hasPrefix("CHAT ") {
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

	/** Whether this user already knows `nickname`: a direct conversation with
	 them is open, or they are in the address book as someone whose activity is
	 tracked.

	 An offer from anyone else is still listed for the user to accept, but it
	 does not download on its own, however the automatic download is set. */
	func isKnownFileTransferPeer(_ nickname: String) -> Bool {
		if findConversation(nickname)?.isDirect == true {
			return true
		}
		return findUserTrackingAddressBookEntry(forNickname: nickname) != nil
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
		guard environment.settings.fileTransferRequestReplyAction != .ignore else { return }
		guard let fileTransfers, let identifier = fileTransfers.addReceiver(
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
		case let .send(filename, address, port, filesize, token):
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
		DirectConnectionLog.transfer.error("Rejected an invalid DCC file-transfer request from \(sender, privacy: .public)")
		print(String(localized: .IRC.glasstualHasReceivedADccRequest(sender)), by: nil, in: nil,
		      as: .dccFileTransfer, command: ChatLineFormat.defaultCommand)
	}
}

/** How many unsolicited DCC offers — a file, or a chat — one connection takes.

 Every offer that gets through costs the user something: a row in the transfer
 list with its observers, a notification and a Dock bounce, or a chat prompt in
 front of whatever they were doing. One sender offering hundreds of files, or a
 channel's worth of people doing it together, is a flood rather than a request,
 so past these ceilings an offer is dropped where it arrived.

 The counts are timestamps rather than a running total so the window slides,
 and the senders remembered are bounded because the network chooses their
 names. */
nonisolated struct DCCOfferThrottle: Sendable {
	/// How long an offer is remembered for.
	static let window: TimeInterval = 60
	/// Offers one sender gets through inside the window.
	static let perSenderLimit = 3
	/// Offers everyone together gets through inside the window.
	static let overallLimit = 10
	/// Senders remembered at once. Past it the least recently heard from is
	/// forgotten, which at worst forgives one sender one offer.
	static let maximumTrackedSenders = 64

	private var offerTimesBySender: [String: [Date]] = [:]

	/// Whether an offer from `sender` — already casefolded, so that one person
	/// cannot reset the count by changing the case of their nickname — may be
	/// taken now, counting it if so.
	mutating func recordOffer(from sender: String, at now: Date) -> Bool {
		let cutoff = now.addingTimeInterval(-Self.window)
		offerTimesBySender = offerTimesBySender.compactMapValues { times in
			let recent = times.filter { $0 > cutoff }
			return recent.isEmpty ? nil : recent
		}

		let senderCount = offerTimesBySender[sender]?.count ?? 0
		let overallCount = offerTimesBySender.values.reduce(0) { $0 + $1.count }
		guard senderCount < Self.perSenderLimit, overallCount < Self.overallLimit else {
			return false
		}

		offerTimesBySender[sender, default: []].append(now)
		if offerTimesBySender.count > Self.maximumTrackedSenders,
		   let oldest = offerTimesBySender.min(by: { ($0.value.last ?? .distantPast) < ($1.value.last ?? .distantPast) })
		{
			offerTimesBySender.removeValue(forKey: oldest.key)
		}
		return true
	}
}
