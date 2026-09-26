// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The application's own channels, which the Help menu and the
/// `glasstual://support-channel` link both open.
enum SupportChannel: String, Sendable {
	case help = "#glasstual"
	case testing = "#glasstual-testing"

	static let serverInfo = "irc.libera.chat +6697"
}

/// Presents merge choices and cancels pending connection requests at termination.
@MainActor
enum ServerConnection {
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

	static func connect(using request: ServerConnectionRequest) {
		let identifier = UUID()
		pendingRequests[identifier] = Task {
			defer { pendingRequests.removeValue(forKey: identifier) }
			guard let chatSession = ChatServices.shared.chatSession else { return }
			await ServerConnectionResolution.resolve(
				using: request,
				sessions: { chatSession.sessions },
				confirmMerge: mergeChoice,
				createConnection: chatSession.createSession(for:)
			)
		}
	}

	private static func mergeChoice(
		_ session: ServerSession,
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
				name: session.name,
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
