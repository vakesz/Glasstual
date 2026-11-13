// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What a `/transport` line asks for.
enum TransportCommandRequest: Equatable {
	case show
	case set(ServerTransport, path: String?)

	/// Reads `/transport`, `/transport irc` and `/transport websocket [path]`,
	/// or nil for anything else.
	init?(_ arguments: CommandArguments) {
		var arguments = arguments
		let name = arguments.next().lowercased()
		let path = arguments.next()
		guard arguments.rest.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

		switch name {
		case "":
			self = .show
		case "irc" where path.isEmpty:
			self = .set(.irc, path: nil)
		case "websocket", "ws":
			self = .set(.webSocket, path: path.isEmpty ? nil : path)
		default:
			return nil
		}
	}
}

extension ServerSession {
	/** `/transport`: the command path of the server properties sheet's
	 connection type. It edits the first configured server, as the sheet's
	 General pane does, and takes effect on the next connect. */
	func dispatchTransportCommand(_ arguments: CommandArguments) {
		guard let request = TransportCommandRequest(arguments) else {
			printDebugInformation(String(localized: .IRC.transportCommandUsage))
			return
		}
		guard var server = config.serverList.first else {
			printDebugInformation(String(localized: .IRC.thereAreNoServersConfigured))
			return
		}

		guard case let .set(transport, path) = request else {
			printTransportStatus(of: server)
			return
		}

		if let path {
			guard ServerTransport.isValidWebSocketPath(path) else {
				printDebugInformation(String(localized: .IRC.transportCommandInvalidPath))
				return
			}
			server.webSocketPath = path
		}
		server.switchTransport(to: transport)

		var updated = config
		updated.serverList[0] = server
		updateConfig(updated)
		chatSession?.save()
		printTransportStatus(of: server)
	}

	private func printTransportStatus(of server: ServerEndpoint) {
		switch server.transport {
		case .irc:
			printDebugInformation(String(localized: .IRC.transportCommandShowsIrc(
				server.serverAddress,
				String(server.serverPort)
			)))
		case .webSocket:
			printDebugInformation(String(localized: .IRC.transportCommandShowsWebSocket(WebSocketAddress.displayURL(
				host: server.serverAddress,
				port: server.serverPort,
				secured: server.prefersSecuredConnection,
				path: server.webSocketPath
			))))
		}
		switch socket?.webSocketFraming {
		case let .negotiated(subprotocol)?:
			printDebugInformation(String(localized: .IRC.webSocketSubprotocolNegotiated(subprotocol.rawValue)))
		case .unnegotiated?:
			printDebugInformation(String(localized: .IRC.webSocketNoSubprotocol))
		case nil:
			break
		}
	}
}
