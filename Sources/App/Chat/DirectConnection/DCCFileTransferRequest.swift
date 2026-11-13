// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// Whether an offer asks for a plain connection or a TLS one. A secure offer
/// names its verb with an `S` prefix, the convention KVIrc started.
enum DCCOfferSecurity: Equatable {
	case plain
	case secure
}

enum DCCFileTransferRequest: Equatable {
	case send(
		filename: String,
		address: String,
		port: UInt16,
		filesize: UInt64,
		token: String?,
		security: DCCOfferSecurity = .plain
	)
	case resume(filename: String, port: UInt16, position: UInt64, token: String?)
	case accept(filename: String, port: UInt16, position: UInt64, token: String?)
	/// A DCC form other clients send that Glasstual does not take part in,
	/// named so it can be declined in so many words rather than reported as
	/// malformed.
	case unsupported(verb: String)
}

enum DCCCommand: String {
	case accept = "ACCEPT"
	case chat = "CHAT"
	case resume = "RESUME"
	case send = "SEND"
	case secureChat = "SCHAT"
	case secureSend = "SSEND"

	var ctcpCommand: String {
		"DCC \(rawValue)"
	}

	/// The verb a file offer goes out under. `RESUME` and `ACCEPT` carry no
	/// prefix for either kind: the transfer they name keeps its own.
	static func offer(for security: DCCOfferSecurity) -> DCCCommand {
		switch security {
		case .plain: .send
		case .secure: .secureSend
		}
	}

	/** Forms that KVIrc and others send but Glasstual declines.

	 A `T` prefix asks for a turbo transfer, in which the receiver sends no
	 acknowledgements, alone or combined with the secure `S` prefix. The
	 `RECV`, `GET` and `RSEND` families reverse who sends. */
	static let unsupportedVerbs: Set<String> = ["TSEND", "TSSEND", "STSEND", "SRECV", "SGET", "SRSEND"]
}

enum DCCFileTransferRequestParser {
	static let maximumFilesize: UInt64 = 1_000_000_000_000

	static func parse(_ source: String) -> DCCFileTransferRequest? {
		var input = CommandTokenizer(source)
		let verb = input.nextUppercaseToken()
		if DCCCommand.unsupportedVerbs.contains(verb) {
			return .unsupported(verb: verb)
		}
		guard let command = DCCCommand(rawValue: verb), command != .chat, command != .secureChat else { return nil }

		let filenameToken = input.remainder.hasPrefix("\"") ? input.nextQuotedToken() : input.nextToken()
		let section2 = input.nextToken()
		let section3 = input.nextToken()
		let section4 = input.nextToken()
		let section5 = input.nextToken()
		let filename = filenameToken.trimmingCharacters(in: .whitespacesAndNewlines).safeFilename

		if command == .send || command == .secureSend {
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
				token: token,
				security: command == .secureSend ? .secure : .plain
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
		token?.allSatisfy(\.isASCIIDigit) ?? true
	}

	private static func validPort(_ value: String, allowsZero: Bool) -> UInt16? {
		guard value.allSatisfy(\.isASCIIDigit), let integer = Int(value), integer >= 0, integer <= Int(UInt16.max),
		      integer > 0 || allowsZero else { return nil }
		return UInt16(integer)
	}

	/// A size or a resume position. An empty file is a file like any other, and
	/// a position of zero is refused where it means nothing, not here.
	private static func validFilesize(_ value: String) -> UInt64? {
		guard value.allSatisfy(\.isASCIIDigit), let size = UInt64(value), size <= maximumFilesize else { return nil }
		return size
	}
}
