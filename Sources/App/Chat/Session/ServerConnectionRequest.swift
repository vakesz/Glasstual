// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

nonisolated struct ServerConnectionOptions: Equatable, Sendable {
	static let externalLink = Self(
		connectWhenCreated: false,
		mergeConnectionIfPossible: true,
		selectFirstChannelAdded: false
	)

	let connectWhenCreated: Bool
	let mergeConnectionIfPossible: Bool
	let selectFirstChannelAdded: Bool
}

/// A parsed endpoint and channels requested by a link or command.
nonisolated struct ServerConnectionRequest: Equatable, Sendable {
	private static let logger = Logger(
		subsystem: LogSubsystem.current,
		category: "ServerConnectionRequest"
	)

	let serverAddress: String
	let serverPort: UInt16
	let serverPassword: String?
	let connectSecurely: Bool
	let channels: [String]
	let options: ServerConnectionOptions

	/// Parses `[-SSL|-TLS] host[:port] [port] [password]`.
	/// URL requests bypass this tokenizer entirely.
	static func parse(
		_ serverInfo: String,
		channels channelList: String?,
		options: ServerConnectionOptions
	) -> Self? { // nonisolated: pure
		guard serverInfo.isEmpty == false else { return nil }

		var tokens = CommandTokenizer(serverInfo)
		var addressAndPort = tokens.nextToken()
		var connectSecurely = false
		if addressAndPort.caseInsensitiveCompare("-SSL") == .orderedSame
			|| addressAndPort.caseInsensitiveCompare("-TLS") == .orderedSame
		{
			connectSecurely = true
			addressAndPort = tokens.nextToken()
		}

		let parsedAddress: String
		var portSuffix = ""
		let openingBracket = addressAndPort.firstIndex(of: "[")
		let closingBracket = addressAndPort.firstIndex(of: "]")

		if let openingBracket,
		   let closingBracket,
		   openingBracket == addressAndPort.startIndex,
		   openingBracket < closingBracket
		{
			let start = addressAndPort.index(after: openingBracket)
			parsedAddress = String(addressAndPort[start ..< closingBracket])
			guard parsedAddress.isIPv6Address else {
				logger.error("Bracketed server address is not IPv6")
				return nil
			}
			portSuffix = String(addressAndPort[addressAndPort.index(after: closingBracket)...])
			guard portSuffix.isEmpty || portSuffix.hasPrefix(":") else { return nil }
		} else if openingBracket == nil, closingBracket == nil {
			if let colon = addressAndPort.firstIndex(of: ":") {
				parsedAddress = String(addressAndPort[..<colon])
				portSuffix = String(addressAndPort[colon...])
			} else {
				parsedAddress = addressAndPort
			}
		} else {
			return nil
		}

		guard parsedAddress.isValidInternetAddress else {
			logger.error("Invalid internet address")
			return nil
		}

		var port: UInt16 = connectSecurely
			? ConnectionDefaults.serverPortSecure
			: ConnectionDefaults.serverPort
		var portText: String?
		if portSuffix.hasPrefix(":") {
			portText = String(portSuffix.dropFirst())
		} else if tokens.remainder.isEmpty == false {
			portText = tokens.nextToken()
		}

		if var portText {
			if portText.hasPrefix("+") {
				portText = String(portText.dropFirst())
				connectSecurely = true
			}
			guard let parsedPort = UInt16(portText), parsedPort > 0 else {
				logger.error("Invalid internet port")
				return nil
			}
			port = parsedPort
		}

		let password = tokens.remainder.isEmpty ? nil : tokens.nextToken()
		return Self(
			serverAddress: parsedAddress.lowercased(),
			serverPort: port,
			serverPassword: password,
			connectSecurely: connectSecurely,
			channels: parseChannels(channelList),
			options: options
		)
	}

	private static func parseChannels(_ channelList: String?) -> [String] { // nonisolated: pure
		guard let channelList, channelList.isEmpty == false else { return [] }
		var channels: [String] = []

		for section in channelList.components(separatedBy: ",") {
			let channel = section.trimmingCharacters(in: .whitespacesAndNewlines)
			guard channel.isChannelName else { continue }
			guard channels.contains(where: {
				$0.caseInsensitiveCompare(channel) == .orderedSame
			}) == false else { continue }
			channels.append(channel)
		}

		return channels
	}
}
