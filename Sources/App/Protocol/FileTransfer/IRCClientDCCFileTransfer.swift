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

enum DCCFileTransferRequestParser {
	static let maximumFilesize: UInt64 = 1_000_000_000_000

	static func parse(_ source: String) -> DCCFileTransferRequest? {
		var input = CommandTokenizer(source)
		let command = input.nextUppercaseToken()
		guard command == "SEND" || command == "RESUME" || command == "ACCEPT" else { return nil }

		let filenameToken = input.remainder.hasPrefix("\"") ? input.nextQuotedToken() : input.nextToken()
		let section2 = input.nextToken()
		let section3 = input.nextToken()
		let section4 = input.nextToken()
		let section5 = input.nextToken()
		let filename = filenameToken.trimmingCharacters(in: .whitespacesAndNewlines).safeFilename

		if command == "SEND" {
			let token = normalizedToken(section5)
			guard !filename.isEmpty, !section2.isEmpty, !section4.isEmpty,
			      validToken(token),
			      let port = validPort(section3, allowsZero: token != nil),
			      let filesize = validFilesize(section4)
			else { return nil }
			return .send(
				filename: filename,
				address: ClientWireUtilities.displayDCCAddress(section2),
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
		if command == "RESUME" {
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
		let base = "\(ClientWireUtilities.escapedDCCFilename(filename)) \(port) \(position)"
		return token.map { "\(base) \($0)" } ?? base
	}

	static func sendArguments(
		filename: String,
		address: String,
		port: UInt16,
		filesize: UInt64,
		token: String?
	) -> String {
		let base = "\(ClientWireUtilities.escapedDCCFilename(filename)) \(address) \(port) \(filesize)"
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
		guard value.allSatisfy(\.isNumber), let integer = Int(value), integer >= 0, integer <= 65535 else {
			return nil
		}
		guard integer > 0 || allowsZero else { return nil }
		return UInt16(integer)
	}

	private static func validFilesize(_ value: String) -> UInt64? {
		guard let size = UInt64(value), size > 0, size <= maximumFilesize else { return nil }
		return size
	}
}

@MainActor
public extension IRCClient {
	@objc(notifyFileTransfer:nickname:filename:filesize:requestIdentifier:)
	func notifyFileTransfer(
		_ type: TXNotificationType,
		nickname: String,
		filename: String,
		filesize totalFilesize: UInt64,
		requestIdentifier identifier: String
	) {
		let description = NotificationStrings.FileTransfer.description(
			for: type,
			filename: filename,
			byteCount: totalFilesize
		)
		_ = notifyEvent(
			type,
			lineType: .undefined,
			target: nil,
			nickname: nickname,
			text: description,
			userInfo: [
				"isFileTransferNotification": true,
				"fileTransferUniqueIdentifier": identifier,
				"fileTransferNotificationType": type.rawValue,
			]
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

	@objc(receivedDCCSend:filename:address:port:filesize:token:)
	func receivedDCCSend(
		_ nickname: String,
		filename: String,
		address: String,
		port: UInt16,
		filesize totalFilesize: UInt64,
		token transferToken: String?
	) {
		print(
			IRCFileTransferStrings.request(nickname: nickname, filename: filename, byteCount: totalFilesize),
			by: nil,
			in: nil,
			as: .dccFileTransfer, command: TVCLogLineDefaultCommandValue
		)
		guard environment.preferences.fileTransferRequestReplyAction != .ignore,
		      let identifier = fileTransferController.addReceiver(
		      	for: self, nickname: nickname, address: address, port: port,
		      	filename: filename, filesize: totalFilesize, token: transferToken
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

	@objc(sendFileResume:port:filename:filesize:token:)
	func sendFileResume(
		_ nickname: String, port: UInt16, filename: String, filesize: UInt64, token: String?
	) {
		sendCTCPQuery(
			nickname,
			command: "DCC RESUME",
			text: DCCFileTransferRequestParser.transferArguments(
				filename: filename, port: port, position: filesize, token: token
			)
		)
	}

	@objc(sendFileResumeAccept:port:filename:filesize:token:)
	func sendFileResumeAccept(
		_ nickname: String, port: UInt16, filename: String, filesize: UInt64, token: String?
	) {
		sendCTCPQuery(
			nickname,
			command: "DCC ACCEPT",
			text: DCCFileTransferRequestParser.transferArguments(
				filename: filename, port: port, position: filesize, token: token
			)
		)
	}

	@objc(sendFile:port:filename:filesize:token:)
	func sendFile(
		_ nickname: String, port: UInt16, filename: String, filesize: UInt64, token: String?
	) {
		guard let address = DCCTransferAddress else { return }
		let arguments = DCCFileTransferRequestParser.sendArguments(
			filename: filename, address: address, port: port, filesize: filesize, token: token
		)
		sendCTCPQuery(nickname, command: "DCC SEND", text: arguments)
		print(
			IRCFileTransferStrings.attempt(nickname: nickname, filename: filename, byteCount: filesize),
			by: nil,
			in: nil,
			as: .dccFileTransfer, command: TVCLogLineDefaultCommandValue
		)
	}

	@objc(DCCSendEscapeFilename:)
	func DCCSendEscapeFilename(_ filename: String) -> String {
		ClientWireUtilities.escapedDCCFilename(filename)
	}

	@objc var DCCTransferAddress: String? {
		guard let address = fileTransferController.IPAddress else { return nil }
		return DCCFormattedAddress(address)
	}

	@objc(DCCFormattedAddress:)
	func DCCFormattedAddress(_ address: String) -> String? {
		let formattedAddress = ClientWireUtilities.wireDCCAddress(address)
		if formattedAddress == nil {
			dccFileTransferLogger.error("The configured file-transfer address is invalid")
		}
		return formattedAddress
	}

	@objc(DCCAddressFromString:)
	func DCCAddressFromString(_ string: String) -> String {
		ClientWireUtilities.displayDCCAddress(string)
	}

	private func processFileTransferRequest(_ request: DCCFileTransferRequest, sender: String) {
		switch request {
		case let .send(filename, address, port, filesize, token):
			// The offer decides which host the client dials, so a peer must
			// not be able to point it at loopback or a private network.
			guard ClientWireUtilities.isDialableDCCAddress(address) else {
				dccFileTransferLogger.error("Refused a DCC SEND offer for a non-routable address")
				printInvalidDCCRequest(from: sender)
				return
			}
			if let token {
				let transfer = fileTransferController.fileTransferSender(
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
				guard let transfer, transfer.transferStatus == .waitingForReceiverToAccept else {
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
				filename: filename
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
				filename: filename
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
		filename: String
	) -> TDCFileTransferDialogTransferController? {
		if let token, port == 0 {
			return fileTransferController.fileTransferSender(
				matchingToken: token,
				client: self,
				peerNickname: sender,
				filename: filename
			)
		}
		if token == nil, port > 0 {
			return fileTransferController.fileTransfer(
				matchingPort: port,
				client: self,
				peerNickname: sender,
				filename: filename
			)
		}
		return nil
	}

	private func printInvalidDCCRequest(from sender: String) {
		dccFileTransferLogger.error("Rejected an invalid DCC file-transfer request from \(sender, privacy: .public)")
		print(IRCDirectChatStrings.unprocessableRequest(sender: sender), by: nil, in: nil,
		      as: .dccFileTransfer, command: TVCLogLineDefaultCommandValue)
	}
}
