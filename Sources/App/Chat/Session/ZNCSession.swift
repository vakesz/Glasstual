// Copyright (c) 2011 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os
import Security

/** What the session knows about the bouncer on the other end.

 ZNC answers a handful of questions differently from a server: it plays back
 history on connect, it can forward the real server's certificate, and its
 modules take commands addressed to them. All of that is one session's worth
 of state, held together rather than as four flags on the session. */
struct ZNCSession {
	/// Whether the server this session reached identified itself as a ZNC.
	var isConnected = false
	/// Whether the `znc.in/cert` module is mid-way through sending the real
	/// server's certificate chain.
	var isSendingCertificateInfo = false
	/// Whether the playback module is replaying history right now.
	var isPlayingBackHistory = false
	/// The PEM chain being assembled, line by line, while
	/// ``isSendingCertificateInfo`` is true.
	var certificateChainText: String?
}

/** What ZNC adds on top of plain IRC: the `/attach`, `/detach` and `/znccert`
 commands, and the rewriting of what its `buffextras` and `playback` modules
 send as ordinary chat. */
@MainActor
extension ServerSession {
	// MARK: - Commands

	func dispatchBouncerCommand(
		_ command: LocalCommand,
		parsed: ParsedUserCommand,
		targetConversation: Conversation?
	) {
		guard znc.isConnected else {
			printDebugInformation(String(localized: .Bouncer.zncConnectionRequired))
			return
		}

		switch command {
		case .znccert:
			presentZNCCertificateChain()
		case .attach, .detach:
			updateZNCAttachment(
				isAttaching: command == .attach,
				channelName: parsed.arguments.rest,
				targetConversation: targetConversation
			)
		default:
			break
		}
	}

	private func updateZNCAttachment(isAttaching: Bool, channelName: String, targetConversation: Conversation?) {
		let name = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
		let target = stringIsChannelName(name) ? findConversation(name) : targetConversation
		guard let target else { return }

		target.autoJoin = isAttaching
		if isAttaching {
			joinUnlistedChannel(target.name)
		} else {
			sendLine("DETACH \(target.name)")
			printDebugInformation(String(localized: .Bouncer.detachConfirmation(target.name)), in: target)
		}
	}

	/** Shows the certificate chain ZNC reported, in the system's trust sheet.

	 ZNC sends the chain as a PEM sequence in a `znc.in/cert` batch, so it is
	 imported before a `SecTrust` can be made of it. */
	private func presentZNCCertificateChain() {
		guard let certificateData = zncBouncerCertificateChainData else {
			printDebugInformation(String(localized: .Bouncer.noInformationAvailable))
			return
		}

		guard let certificates = Self.certificates(fromPEMSequence: certificateData),
		      let trust = Self.basicTrust(for: certificates)
		else {
			printDebugInformation(String(localized: .Bouncer.certificateConversionError))
			return
		}

		environment.services.certificateTrust.presentChain(
			trust,
			title: networkName ?? serverAddress ?? "",
			closeButton: String(localized: .Bouncer.closeButton)
		)
	}

	private static func certificates(fromPEMSequence data: Data) -> [SecCertificate]? {
		var parameters = SecItemImportExportKeyParameters()
		parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
		parameters.flags = []
		var format = SecExternalFormat.formatPEMSequence
		var type = SecExternalItemType.itemTypeCertificate
		var importedItems: CFArray?
		let status = SecItemImport(
			data as CFData,
			nil,
			&format,
			&type,
			[],
			&parameters,
			nil,
			&importedItems
		)

		guard status == errSecSuccess, let certificates = importedItems as? [SecCertificate],
		      certificates.isEmpty == false
		else { return nil }
		return certificates
	}

	/// A basic X.509 trust over the chain. The bouncer's certificate is not the
	/// one this connection was made with, so there is no host name to check it
	/// against; the panel is showing the chain, not judging it.
	private static func basicTrust(for certificates: [SecCertificate]) -> SecTrust? {
		var trust: SecTrust?
		guard SecTrustCreateWithCertificates(
			certificates as CFArray,
			SecPolicyCreateBasicX509(),
			&trust
		) == errSecSuccess else { return nil }
		return trust
	}

	// MARK: - Inbound

	/** The line as the rest of the session should see it, or `nil` to drop it.

	 ZNC's `buffextras` module replays joins, parts, mode changes and the rest
	 as ordinary `PRIVMSG` text, and its `playback` module announces when it has
	 cleared a buffer. Both are turned back into what they describe here, before
	 anything else in the session reads the message. */
	func interceptZNCServerInput(_ message: Message) -> Message? {
		guard znc.isConnected, message.remoteCommand == .privmsg, message.params.count == 2 else {
			return message
		}

		guard let sender = message.senderNickname else { return message }
		if nickname(sender, isZNCUser: "buffextras") {
			return interceptZNCBufferExtras(message)
		}
		if nickname(sender, isZNCUser: "playback") {
			return interceptZNCPlayback(message)
		}
		return message
	}

	private func interceptZNCPlayback(_ message: Message) -> Message? {
		guard isCapabilityEnabled(.zncPlaybackModule) else { return message }
		let body = message.params[1]
		if body.hasPrefix("The playback buffer for ["),
		   body.contains("] channels matching ["),
		   body.hasSuffix("] has been cleared.")
		{
			return nil
		}
		return message
	}

	/// ZNC writes a `*status` notice when the bouncer loses its own connection
	/// to IRC. Every channel is then parted as far as the network is concerned,
	/// so they are deactivated rather than left looking joined.
	func handleZNCStatusNotice(_ message: Message) {
		guard znc.isConnected, message.remoteCommand == .privmsg,
		      let sender = message.senderNickname, nickname(sender, isZNCUser: "status"),
		      message.sequence.hasPrefix("Disconnected from IRC")
		else { return }

		for conversation in conversationList where conversation.isActive && conversation.name.hasPrefix("~#") == false {
			conversation.deactivate()
		}
		output?.reloadChatItemGroup(self)
	}

	// MARK: - buffextras

	private func interceptZNCBufferExtras(_ message: Message) -> Message? {
		var parameters = message.params
		var body = CommandTokenizer(parameters[1].normalizingSpaces)
		let hostmask = body.nextToken()
		guard hostmask.isEmpty == false else { return message }

		var sender = message.sender
		/* The protocol maximum rather than the network's NICKLEN: a replayed
		 line is about whoever the bouncer recorded, on whatever network it was
		 connected to then, which is not necessarily this one. */
		if let components = Hostmask(parsing: hostmask) {
			guard components.nickname != userNickname else { return nil }
			sender.nickname = components.nickname
			sender.username = components.username
			sender.address = components.address
			sender.isServer = false
		} else {
			sender.nickname = hostmask
			sender.isServer = true
		}
		sender.hostmask = hostmask

		let text = String(body.remainder)
		guard let replay = Self.replayedEvent(in: text) else {
			guard text.hasPrefix("changed the topic to: ") == false else { return nil }
			return applyingBufferExtras(to: message, sender: sender, command: nil, parameters: parameters)
		}

		parameters.remove(at: 1)
		parameters.append(contentsOf: replay.parameters)
		return applyingBufferExtras(
			to: message,
			sender: sender,
			command: replay.command,
			parameters: parameters
		)
	}

	private func applyingBufferExtras(
		to message: Message,
		sender: Prefix,
		command: RemoteCommand?,
		parameters: [String]
	) -> Message {
		var rewritten = message
		rewritten.sender = sender
		if let command {
			rewritten.rewrite(as: command)
		}
		rewritten.params = parameters
		rewritten.isPrintOnlyMessage = true
		return rewritten
	}

	/// The IRC event one line of `buffextras` text describes, and the parameters
	/// that replace the text.
	private static func replayedEvent(in text: String) -> (command: RemoteCommand, parameters: [String])? {
		if text == "joined" {
			return (.join, [])
		}
		if let match = text.wholeMatch(of: /is now known as (\S+)/) {
			return (.nick, [String(match.1)])
		}
		if let match = text.wholeMatch(of: /parted with message: \[(.*)\]|parted: (.*)/) {
			return (.part, [String(match.1 ?? match.2 ?? "")])
		}
		if let match = text.wholeMatch(of: /quit with message: \[(.*)\]|quit: (.*)/) {
			return (.quit, [String(match.1 ?? match.2 ?? "")])
		}
		if let match = text.wholeMatch(of: /kicked (\S+) with reason: (.*)|kicked (\S+) Reason: \[(.*)\]/) {
			/* A group that did not take part in the match is not reported at
			 all, and an empty reason is no reason: the KICK handler reads a
			 missing third parameter as no comment. */
			let captures = [match.1, match.2, match.3, match.4].compactMap { $0.map(String.init) }
			return (.kick, Array(captures.filter { $0.isEmpty == false }.prefix(2)))
		}
		if let match = text.wholeMatch(of: /set mode: (\S+)(.*)/) {
			/* The mode string and each of its arguments are separate IRC
			 parameters. Joining them made "+ov nick1 nick2" one parameter,
			 which the MODE handler cannot read. */
			let arguments = String(match.2)
				.trimmingCharacters(in: .whitespaces)
				.components(separatedBy: " ")
				.filter { $0.isEmpty == false }
			return (.mode, [String(match.1)] + arguments)
		}
		return nil
	}
}

private let zncLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "ZNCSession"
)

extension ServerSession {
	func clearZNCPlayback(for conversation: Conversation) {
		guard znc.isConnected else { return }
		clearPlayback(for: conversation)
	}

	func nicknameIsZNCUser(_ nickname: String) -> Bool {
		znc.isConnected && nickname.hasPrefix(ServerQuirks.ZNC.modulePrefix)
	}

	/// Folded the way the server folds nicknames, so `*Status` and `*status`
	/// name the same module.
	func nickname(_ nickname: String, isZNCUser zncNickname: String) -> Bool {
		guard let moduleNickname = nicknameAsZNCUser(zncNickname) else { return false }
		return casefoldNickname(nickname) == casefoldNickname(moduleNickname)
	}

	func nicknameAsZNCUser(_ nickname: String) -> String? {
		guard znc.isConnected else { return nil }
		return ServerQuirks.ZNC.nickname(forModuleNamed: nickname)
	}

	/** Whether `message` may raise a notification.

	 Chat history the session asked for never does. Past that the question is
	 only what a bouncer replays: a playback batch is recognised by its type
	 where the server negotiated `batch`, and by the replay flag where it did
	 not. */
	func isSafeToPostNotification(for message: Message, in conversation: Conversation?) -> Bool {
		guard batchMessage(ofType: ServerQuirks.chatHistoryBatchType, containing: message) == nil else {
			return false
		}

		guard znc.isConnected else { return true }

		if config.zncIgnoreUserNotifications, conversation.map({ nicknameIsZNCUser($0.name) }) == true {
			return false
		}

		guard config.zncIgnorePlaybackNotifications else { return true }

		if isCapabilityEnabled(.batch) {
			return message.parentBatchMessage?.batchType != ServerQuirks.ZNC.playbackBatchType
		}

		return message.isReplayed == false
	}

	func detectZNC(from message: Message) {
		guard znc.isConnected == false, message.senderIsServer else { return }
		guard message.senderNickname == ServerQuirks.ZNC.serverName else { return }

		znc.isConnected = true
		zncLogger.info("ZNC detected")
	}

	func sendCommand(_ command: String, toZNCModuleNamed module: String) {
		guard let destination = nicknameAsZNCUser(module) else { return }
		sendLine("ZNC \(destination) \(command)")
	}

	// MARK: - Playback

	func clearPlayback(for conversation: Conversation) {
		guard isCapabilityEnabled(.playback) else { return }
		guard conversation.isDirect, conversation.isDirectForZNCUser == false else { return }

		sendPlaybackCommand("clear \(conversation.name)")
	}

	func requestPlayback() {
		guard isCapabilityEnabled(.playback) else { return }

		/* chathistory is requested per target as channels are joined and only
		 fetches what the local scrollback lacks. It wins over a bouncer replaying
		 everything. */
		guard isCapabilityEnabled(.chatHistory) == false else { return }

		sendPlaybackCommand(zncPlaybackCommand(
			successfulConnects: successfulConnects,
			onlyLatestOnFirstConnect: config.zncOnlyPlaybackLatest,
			lastMessageServerTime: lastMessageServerTime
		))
	}

	/// The module takes commands addressed to it once the bouncer is known to be
	/// a ZNC; before that the only way to reach it is as an ordinary direct
	/// conversation.
	private func sendPlaybackCommand(_ command: String) {
		if znc.isConnected {
			sendCommand(command, toZNCModuleNamed: ServerQuirks.ZNC.playbackModule)
		} else {
			send(.privmsg, arguments: ["*playback", command])
		}
	}
}

/** The ZNC playback request for this connect.

 A reconnect asks for everything since the last line the session saw; a first
 connect asks for everything, unless the user only wants the latest. */
func zncPlaybackCommand(
	successfulConnects: UInt,
	onlyLatestOnFirstConnect: Bool,
	lastMessageServerTime: TimeInterval
) -> String {
	let shouldUseTimestamp = (
		successfulConnects > 1 || (successfulConnects == 1 && onlyLatestOnFirstConnect)
	) && lastMessageServerTime > 0

	guard shouldUseTimestamp else { return "play * 0" }
	return String(format: "play * %.0f", lastMessageServerTime)
}
