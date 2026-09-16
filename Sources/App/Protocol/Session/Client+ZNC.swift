/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2011 - 2018 Codeux Software, LLC & respective contributors.
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

import AppKit
import CocoaExtensions
import Security

/** What the client knows about the bouncer on the other end.

 ZNC answers a handful of questions differently from a server: it plays back
 history on connect, it can forward the real server's certificate, and its
 modules take commands addressed to them. All of that is one session's worth
 of state, held together rather than as four flags on the client. */
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
extension Client {
	// MARK: - Commands

	func dispatchBouncerCommand(_ parsed: ParsedUserCommand, targetChannel: Channel?) {
		guard let command = parsed.localCommand else { return }
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
				targetChannel: targetChannel
			)
		default:
			break
		}
	}

	private func updateZNCAttachment(isAttaching: Bool, channelName: String, targetChannel: Channel?) {
		let name = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
		let channel = stringIsChannelName(name) ? findChannel(name) : targetChannel
		guard let channel else { return }

		channel.autoJoin = isAttaching
		if isAttaching {
			joinUnlistedChannel(channel.name)
		} else {
			sendLine("DETACH \(channel.name)")
			printDebugInformation(String(localized: .Bouncer.detachConfirmation(channel.name)), in: channel)
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

		TrustPanelPresenter.present(
			in: NSApp.mainWindow,
			body: "",
			title: networkName ?? serverAddress ?? "",
			defaultButton: String(localized: .Bouncer.closeButton),
			alternateButton: nil,
			trust: trust
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

	/** The line as the rest of the client should see it, or `nil` to drop it.

	 ZNC's `buffextras` module replays joins, parts, mode changes and the rest
	 as ordinary `PRIVMSG` text, and its `playback` module announces when it has
	 cleared a buffer. Both are turned back into what they describe here, before
	 anything else in the client reads the message. */
	func interceptZNCServerInput(_ message: Message) -> Message? {
		guard znc.isConnected, message.command == "PRIVMSG", message.params.count == 2 else {
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
		guard znc.isConnected, message.command == "PRIVMSG",
		      let sender = message.senderNickname, nickname(sender, isZNCUser: "status"),
		      message.sequence.hasPrefix("Disconnected from IRC")
		else { return }

		for channel in channelList where channel.isActive && channel.name.hasPrefix("~#") == false {
			channel.deactivate()
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
		command: String?,
		parameters: [String]
	) -> Message {
		let copy = message.duplicate()
		copy.sender = sender
		if let command {
			copy.command = command
		}
		copy.params = parameters
		copy.isPrintOnlyMessage = true
		return copy
	}

	/// The IRC event one line of `buffextras` text describes, and the parameters
	/// that replace the text.
	private static func replayedEvent(in text: String) -> (command: String, parameters: [String])? {
		if text == "joined" {
			return ("JOIN", [])
		}
		if let match = text.wholeMatch(of: /is now known as (\S+)/) {
			return ("NICK", [String(match.1)])
		}
		if let match = text.wholeMatch(of: /parted with message: \[(.*)\]|parted: (.*)/) {
			return ("PART", [String(match.1 ?? match.2 ?? "")])
		}
		if let match = text.wholeMatch(of: /quit with message: \[(.*)\]|quit: (.*)/) {
			return ("QUIT", [String(match.1 ?? match.2 ?? "")])
		}
		if let match = text.wholeMatch(of: /kicked (\S+) with reason: (.*)|kicked (\S+) Reason: \[(.*)\]/) {
			/* A group that did not take part in the match is not reported at
			 all, and an empty reason is no reason: the KICK handler reads a
			 missing third parameter as no comment. */
			let captures = [match.1, match.2, match.3, match.4].compactMap { $0.map(String.init) }
			return ("KICK", Array(captures.filter { $0.isEmpty == false }.prefix(2)))
		}
		if let match = text.wholeMatch(of: /set mode: (\S+)(.*)/) {
			/* The mode string and each of its arguments are separate IRC
			 parameters. Joining them made "+ov nick1 nick2" one parameter,
			 which the MODE handler cannot read. */
			let arguments = String(match.2)
				.trimmingCharacters(in: .whitespaces)
				.components(separatedBy: " ")
				.filter { $0.isEmpty == false }
			return ("MODE", [String(match.1)] + arguments)
		}
		return nil
	}
}
