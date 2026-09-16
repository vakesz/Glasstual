/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
			guard (channel as NSString).isChannelName else { continue }
			guard channels.contains(where: {
				$0.caseInsensitiveCompare(channel) == .orderedSame
			}) == false else { continue }
			channels.append(channel)
		}

		return channels
	}
}

/// What the reader chose when a link named a server they are already connected
/// to. Cancel is a real answer: a link that opens an alert with no way out is a
/// link that makes a connection whether or not it was wanted.
enum ServerConnectionMergeChoice: Sendable {
	case useExisting
	case createNew
	case cancel
}

/// The application's own channels, which the Help menu and the
/// `glasstual://support-channel` link both open.
enum SupportChannel: String, Sendable {
	case help = "#glasstual"
	case testing = "#glasstual-testing"

	static let serverInfo = "irc.libera.chat +6697"
}

@MainActor
enum ServerConnectionController {
	private static var pendingRequests: [UUID: Task<Void, Never>] = [:]

	static func cancelPendingRequests() {
		pendingRequests.values.forEach { $0.cancel() }
		pendingRequests.removeAll()
	}

	static func connect(to channel: SupportChannel) {
		connect(
			to: SupportChannel.serverInfo,
			channels: channel.rawValue,
			options: ServerConnectionOptions(
				connectWhenCreated: true,
				mergeConnectionIfPossible: true,
				selectFirstChannelAdded: true
			)
		)
	}

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
		using request: ServerConnectionRequest
	) {
		let identifier = UUID()
		pendingRequests[identifier] = Task {
			defer { pendingRequests.removeValue(forKey: identifier) }
			await resolve(using: request)
		}
	}

	static func resolve(
		using request: ServerConnectionRequest,
		clients: [Client]? = nil,
		confirmMerge: @MainActor (Client, String, [String]) async -> ServerConnectionMergeChoice = mergeChoice,
		mergeConnection: @MainActor (ServerConnectionRequest, Client) -> Void = merge,
		createConnection: @MainActor (ServerConnectionRequest) -> Void = createClient
	) async {
		guard !Task.isCancelled else { return }
		var existingClient: Client?
		/* Whether or not the link names a channel. A link to a server alone
		 used to skip this, so every one added another saved copy of a server
		 the reader already had. */
		if request.options.mergeConnectionIfPossible {
			for candidate in clients ?? ClientEnvironment.shared.clientDirectory?.clientList ?? []
				where await credentialsAllowReuse(candidate, for: request)
			{
				existingClient = candidate
				break
			}
		}
		guard !Task.isCancelled else { return }

		/* The question is about adding channels to that connection. With no
		 channel to add there is nothing to ask, and the existing connection is
		 the one the link means. */
		if let matchedClient = existingClient, request.channels.isEmpty == false {
			let session = matchedClient.startup.identifier
			let connection = matchedClient.socket?.uniqueIdentifier
			let choice = await confirmMerge(matchedClient, request.serverAddress, request.channels)
			guard !Task.isCancelled else { return }
			switch choice {
			case .cancel: return
			case .createNew:
				createConnection(request)
				return
			case .useExisting: break
			}
			let stillMatches = await credentialsAllowReuse(matchedClient, for: request)
			guard !Task.isCancelled, !matchedClient.isTerminating,
			      matchedClient.startup.identifier == session,
			      matchedClient.socket?.uniqueIdentifier == connection,
			      stillMatches,
			      (clients ?? ClientEnvironment.shared.clientDirectory?.clientList ?? []).contains(where: { $0 === matchedClient })
			else { return }
		}

		if let existingClient {
			mergeConnection(request, existingClient)
		} else {
			createConnection(request)
		}
	}

	static func canReuse(_ client: Client, for request: ServerConnectionRequest) -> Bool {
		let config = client.config
		guard config.serverAddress?.caseInsensitiveCompare(request.serverAddress) == .orderedSame,
		      config.serverPort == request.serverPort,
		      config.prefersSecuredConnection == request.connectSecurely,
		      config.cipherSuites == .default,
		      request.connectSecurely == false || config.validateServerCertificateChain
		else { return false }
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

	private static func credentialsAllowReuse(_ client: Client, for request: ServerConnectionRequest) async -> Bool {
		guard canReuse(client, for: request) else { return false }
		guard let password = request.serverPassword else { return true }
		guard let server = client.config.serverList.first else { return false }
		let passwords = await KeychainSecretLoader.passwords(for: [server.keychainItem])
		guard !Task.isCancelled, !client.isTerminating,
		      client.config.serverList.first == server, canReuse(client, for: request) else { return false }
		return server.pendingServerPassword.value(orStored: passwords[server.keychainItem]) == password
	}

	private static func merge(_ request: ServerConnectionRequest, into client: Client) {
		var firstChannel: Channel?
		for name in request.channels {
			let channel = client.findChannelOrCreate(name, isPrivateMessage: false)
			firstChannel = firstChannel ?? channel
			if request.options.connectWhenCreated, let channel {
				client.join(channel)
			}
		}

		client.clientDirectory?.save()
		if request.options.selectFirstChannelAdded, let firstChannel {
			client.output?.select(firstChannel)
		} else if request.channels.isEmpty {
			/* A link to the server alone opens that server. */
			client.output?.select(client)
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

		guard let client = ClientEnvironment.shared.clientDirectory?.createClient(with: config) else {
			return
		}
		ClientEnvironment.shared.clientDirectory?.save()

		if request.options.connectWhenCreated {
			client.connect()
		}
		if request.options.selectFirstChannelAdded {
			client.selectFirstChannelInChannelList()
		}
	}

	private static func mergeChoice(
		_ client: Client,
		address: String,
		channels: [String]
	) async -> ServerConnectionMergeChoice {
		let hasMultipleChannels = channels.count > 1
		let channelNames = hasMultipleChannels ? channels.joined(separator: ", ") : channels[0]

		/* Three buttons, because the question has three answers. Making
		 "Create New Connection" the Escape button meant dismissing the alert
		 connected somewhere the reader had not agreed to go. */
		let outcome = await Alerts.run(AlertRequest(
			title: PromptStrings.ConnectionLink.title(
				serverAddress: address,
				channelNames: channelNames,
				includesMultipleChannels: hasMultipleChannels
			),
			body: PromptStrings.ConnectionLink.existingConnectionBody(
				name: client.name,
				includesMultipleChannels: hasMultipleChannels
			),
			defaultButton: PromptStrings.ConnectionLink.useExistingConnectionButtonTitle,
			alternateButton: PromptStrings.Action.cancel,
			otherButton: PromptStrings.ConnectionLink.createNewConnectionButtonTitle,
			style: .warning
		), on: .mainWindow)

		return switch outcome.response {
		case .default: .useExisting
		case .other: .createNew
		case .alternate: .cancel
		}
	}
}
