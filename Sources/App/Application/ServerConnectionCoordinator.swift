/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import os

nonisolated struct ServerConnectionOptions: Equatable, Sendable { // nonisolated: value
	static let externalLink = Self(
		connectWhenCreated: false,
		mergeConnectionIfPossible: true,
		selectFirstChannelAdded: false
	)

	let connectWhenCreated: Bool
	let mergeConnectionIfPossible: Bool
	let selectFirstChannelAdded: Bool
}

nonisolated struct ServerConnectionRequest: Equatable, Sendable { // nonisolated: value
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "ServerConnectionRequest"
	)

	let serverAddress: String
	let serverPort: UInt16
	let serverPassword: String?
	let connectSecurely: Bool
	let channels: [String]
	let options: ServerConnectionOptions

	/// Legacy command adapter for `[-SSL] host[:port] [password]`.
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

		guard (parsedAddress as NSString).isValidInternetAddress else {
			logger.error("Invalid internet address")
			return nil
		}

		var port: UInt16 = connectSecurely
			? IRCConnectionDefaults.serverPortSecure
			: IRCConnectionDefaults.serverPort
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
			guard (channel as NSString).isChannelName else { continue }
			guard channels.contains(where: {
				$0.caseInsensitiveCompare(channel) == .orderedSame
			}) == false else { continue }
			channels.append(channel)
		}

		return channels
	}
}

@MainActor
enum ServerConnectionCoordinator {
	static func connect(
		to serverInfo: String,
		channels: String?,
		options: ServerConnectionOptions
	) {
		guard let request = ServerConnectionRequest.parse(serverInfo, channels: channels, options: options) else {
			return
		}
		connect(using: request)
	}

	static func connect(
		using request: ServerConnectionRequest,
		clients: [IRCClient]? = nil,
		confirmMerge: @MainActor (IRCClient, String, [String]) -> Bool = shouldMerge,
		mergeConnection: @MainActor (ServerConnectionRequest, IRCClient) -> Void = merge,
		createConnection: @MainActor (ServerConnectionRequest) -> Void = createClient
	) {
		var existingClient: IRCClient?
		if request.options.mergeConnectionIfPossible, request.channels.isEmpty == false {
			existingClient = (clients ?? ClientEnvironment.shared.world?.clientList ?? []).first {
				canReuse($0, for: request)
			}
		}

		if let matchedClient = existingClient,
		   confirmMerge(matchedClient, request.serverAddress, request.channels) == false
		{
			existingClient = nil
		}

		if let existingClient {
			mergeConnection(request, existingClient)
		} else {
			createConnection(request)
		}
	}

	static func canReuse(_ client: IRCClient, for request: ServerConnectionRequest) -> Bool {
		let config = client.config
		guard config.serverAddress?.caseInsensitiveCompare(request.serverAddress) == .orderedSame,
		      config.serverPort == request.serverPort,
		      config.prefersSecuredConnection == request.connectSecurely,
		      config.cipherSuites == .default,
		      request.connectSecurely == false || config.validateServerCertificateChain
		else { return false }
		if let password = request.serverPassword,
		   config.serverList.first?.serverPassword != password
		{
			return false
		}
		// A live connection can still be using the endpoint from before an edit.
		if let socket = client.socket {
			guard socket.config.serverAddress.caseInsensitiveCompare(request.serverAddress) == .orderedSame,
			      socket.config.serverPort == request.serverPort,
			      socket.config.connectionPrefersSecuredConnection == request.connectSecurely,
			      socket.config.cipherSuites == .default,
			      request.connectSecurely == false || socket.config.connectionShouldValidateCertificateChain
			else { return false }
		}
		return true
	}

	private static func merge(_ request: ServerConnectionRequest, into client: IRCClient) {
		var firstChannel: IRCChannel?
		for name in request.channels {
			let channel = client.findChannelOrCreate(name, isPrivateMessage: false)
			firstChannel = firstChannel ?? channel
			if request.options.connectWhenCreated, let channel {
				client.join(channel)
			}
		}

		client.world?.save()
		if request.options.selectFirstChannelAdded, let firstChannel {
			client.output?.selectItem(firstChannel)
		}
	}

	private static func createClient(for request: ServerConnectionRequest) {
		var config = ClientConfig()
		config.connectionName = request.serverAddress

		var server = Server(
			serverAddress: request.serverAddress,
			serverPort: request.serverPort,
			prefersSecuredConnection: request.connectSecurely
		)
		server.serverPassword = request.serverPassword
		config.serverList = [server]
		config.channelList = request.channels.map(ChannelConfig.seed(withName:))

		guard let client = ClientEnvironment.shared.world?.createClient(with: config) else {
			return
		}
		ClientEnvironment.shared.world?.save()

		if request.options.connectWhenCreated {
			client.connect()
		}
		if request.options.selectFirstChannelAdded {
			client.selectFirstChannelInChannelList()
		}
	}

	private static func shouldMerge(_ client: IRCClient, address: String, channels: [String]) -> Bool {
		let hasMultipleChannels = channels.count > 1
		let channelNames = hasMultipleChannels ? channels.joined(separator: ", ") : channels[0]

		return Alerts.modalAlert(
			withMessage: PromptStrings.ConnectionLink.existingConnectionBody(
				name: client.name,
				includesMultipleChannels: hasMultipleChannels
			),
			title: PromptStrings.ConnectionLink.title(
				serverAddress: address,
				channelNames: channelNames,
				includesMultipleChannels: hasMultipleChannels
			),
			defaultButton: PromptStrings.ConnectionLink.useExistingConnectionButtonTitle,
			alternateButton: PromptStrings.ConnectionLink.createNewConnectionButtonTitle
		)
	}
}
