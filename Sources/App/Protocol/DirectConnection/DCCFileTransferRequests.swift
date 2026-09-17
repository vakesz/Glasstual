// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private let dccFileTransferLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "DCCFileTransfer"
)

enum DCCFileTransferRequest: Equatable {
	case send(filename: String, address: String, port: UInt16, filesize: UInt64, token: String?)
	case resume(filename: String, port: UInt16, position: UInt64, token: String?)
	case accept(filename: String, port: UInt16, position: UInt64, token: String?)
}

enum DCCCommand: String {
	case accept = "ACCEPT"
	case chat = "CHAT"
	case resume = "RESUME"
	case send = "SEND"

	var ctcpCommand: String {
		"DCC \(rawValue)"
	}
}

enum DCCFileTransferRequestParser {
	static let maximumFilesize: UInt64 = 1_000_000_000_000

	static func parse(_ source: String) -> DCCFileTransferRequest? {
		var input = CommandTokenizer(source)
		guard let command = DCCCommand(rawValue: input.nextUppercaseToken()), command != .chat else { return nil }

		let filenameToken = input.remainder.hasPrefix("\"") ? input.nextQuotedToken() : input.nextToken()
		let section2 = input.nextToken()
		let section3 = input.nextToken()
		let section4 = input.nextToken()
		let section5 = input.nextToken()
		let filename = filenameToken.trimmingCharacters(in: .whitespacesAndNewlines).safeFilename

		if command == .send {
			let token = normalizedToken(section5)
			guard !filename.isEmpty, !section2.isEmpty, !section4.isEmpty,
			      validToken(token),
			      let port = validPort(section3, allowsZero: token != nil),
			      let filesize = validFilesize(section4)
			else { return nil }
			return .send(
				filename: filename,
				address: DCCWireFormat.displayAddress(section2),
				port: port,
				filesize: filesize,
				token: token
			)
		}

		let token = normalizedToken(section4)
		guard !filename.isEmpty, !section2.isEmpty,
		      validToken(token),
		      let port = validPort(section2, allowsZero: token != nil),
		      let position = validFilesize(section3)
		else { return nil }
		if command == .resume {
			return .resume(filename: filename, port: port, position: position, token: token)
		}
		return .accept(filename: filename, port: port, position: position, token: token)
	}

	static func transferArguments(
		filename: String,
		port: UInt16,
		position: UInt64,
		token: String?
	) -> String {
		let base = "\(DCCWireFormat.escapedFilename(filename)) \(port) \(position)"
		return token.map { "\(base) \($0)" } ?? base
	}

	static func sendArguments(
		filename: String,
		address: String,
		port: UInt16,
		filesize: UInt64,
		token: String?
	) -> String {
		let base = "\(DCCWireFormat.escapedFilename(filename)) \(address) \(port) \(filesize)"
		return token.flatMap { $0.isEmpty ? nil : "\(base) \($0)" } ?? base
	}

	private static func normalizedToken(_ token: String) -> String? {
		let normalized = token.hasPrefix("T") ? String(token.dropFirst()) : token
		return normalized.isEmpty ? nil : normalized
	}

	private static func validToken(_ token: String?) -> Bool {
		token?.allSatisfy(\.isNumber) ?? true
	}

	private static func validPort(_ value: String, allowsZero: Bool) -> UInt16? {
		guard value.allSatisfy(\.isNumber), let integer = Int(value), integer >= 0, integer <= Int(UInt16.max) else {
			return nil
		}
		guard integer > 0 || allowsZero else { return nil }
		return UInt16(integer)
	}

	/// A size or a resume position. An empty file is a file like any other, and
	/// a position of zero is refused where it means nothing, not here.
	private static func validFilesize(_ value: String) -> UInt64? {
		guard value.allSatisfy(\.isNumber), let size = UInt64(value), size <= maximumFilesize else { return nil }
		return size
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

@MainActor
extension Client {
	func notifyFileTransfer(
		_ type: NotificationEvent,
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
			userInfo: NotificationPayload(
				clientIdentifier: uniqueIdentifier,
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
			dccFileTransferLogger.notice("Dropped a DCC offer past the offer throttle")
			return false
		}
		return true
	}

	/** Whether this user already knows `nickname`: a query with them is open,
	 or they are in the address book as someone whose activity is tracked.

	 An offer from anyone else is still listed for the user to accept, but it
	 does not download on its own, however the automatic download is set. */
	func isKnownFileTransferPeer(_ nickname: String) -> Bool {
		if findChannel(nickname)?.isPrivateMessage == true {
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
			as: .dccFileTransfer, command: LogLineFormat.defaultCommand
		)
		guard environment.preferences.fileTransferRequestReplyAction != .ignore else { return }
		guard let identifier = fileTransferCenter.addReceiver(
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
			as: .dccFileTransfer, command: LogLineFormat.defaultCommand
		)
	}

	var DCCTransferAddress: String? {
		guard let address = fileTransferCenter.ipAddress else { return nil }
		return DCCFormattedAddress(address)
	}

	func DCCFormattedAddress(_ address: String) -> String? {
		let formattedAddress = DCCWireFormat.wireAddress(address)
		if formattedAddress == nil {
			dccFileTransferLogger.error("The configured file-transfer address is invalid")
		}
		return formattedAddress
	}

	private func processFileTransferRequest(_ request: DCCFileTransferRequest, sender: String) {
		switch request {
		case let .send(filename, address, port, filesize, token):
			/* An active offer decides which host the client dials, so a peer
			 must not be able to point it at loopback or a private network. A
			 passive one — port zero — is dialled by the peer instead, and a
			 peer behind NAT names the private address it knows itself by. */
			guard port == 0 || DCCWireFormat.isDialableAddress(address) else {
				dccFileTransferLogger.error("Refused a DCC SEND offer for a non-routable address")
				printInvalidDCCRequest(from: sender)
				return
			}
			if let token {
				let transfer = fileTransferCenter.fileTransferSender(
					matchingToken: token,
					client: self,
					peerNickname: sender,
					filename: filename
				)
				if port == 0 {
					guard transfer == nil else {
						printInvalidDCCRequest(from: sender)
						return
					}
					receivedDCCSend(
						sender, filename: filename, address: address, port: port,
						filesize: filesize, token: token
					)
					return
				}
				guard let transfer, transfer.transferStatus == .waitingForReceiverToAccept,
				      transfer.totalFilesize == filesize
				else {
					printInvalidDCCRequest(from: sender)
					return
				}
				transfer.didReceiveSendRequest(address, hostPort: port)
				return
			}
			receivedDCCSend(sender, filename: filename, address: address, port: port, filesize: filesize, token: nil)
		case let .resume(filename, port, position, token):
			guard let transfer = matchingFileTransfer(
				port: port,
				token: token,
				sender: sender,
				filename: filename,
				isSender: true
			),
				transfer.transferStatus == .waitingForReceiverToAccept || transfer
				.transferStatus == .isListeningAsSender
			else {
				printInvalidDCCRequest(from: sender)
				return
			}
			transfer.didReceiveResumeRequest(position)
		case let .accept(filename, port, position, token):
			guard let transfer = matchingFileTransfer(
				port: port,
				token: token,
				sender: sender,
				filename: filename,
				isSender: false
			),
				transfer.transferStatus == .waitingForResumeAccept
			else {
				printInvalidDCCRequest(from: sender)
				return
			}
			transfer.didReceiveResumeAccept(position)
		}
	}

	private func matchingFileTransfer(
		port: UInt16,
		token: String?,
		sender: String,
		filename: String,
		isSender: Bool
	) -> FileTransfer? {
		if let token, port == 0 {
			return fileTransferCenter.fileTransfer(
				matchingToken: token,
				client: self,
				peerNickname: sender,
				filename: filename,
				isSender: isSender
			)
		}
		if token == nil, port > 0 {
			return fileTransferCenter.fileTransfer(
				matchingPort: port,
				client: self,
				peerNickname: sender,
				filename: filename,
				isSender: isSender
			)
		}
		return nil
	}

	private func printInvalidDCCRequest(from sender: String) {
		dccFileTransferLogger.error("Rejected an invalid DCC file-transfer request from \(sender, privacy: .public)")
		print(String(localized: .IRC.glasstualHasReceivedADccRequest(sender)), by: nil, in: nil,
		      as: .dccFileTransfer, command: LogLineFormat.defaultCommand)
	}
}
