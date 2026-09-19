// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

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
