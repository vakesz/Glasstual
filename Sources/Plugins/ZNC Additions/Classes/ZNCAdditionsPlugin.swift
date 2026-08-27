/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import GlasstualPluginKit
import Security
import SecurityInterface

@objc(TPI_ZNCAdditions)
final class ZNCAdditionsPlugin: NSObject, GlasstualPlugin, PluginCommandHandling, PluginServerInputHandling,
	PluginServerMessageIntercepting, @unchecked Sendable
{
	var subscribedUserInputCommands: [String] {
		["detach", "attach", "znccert"]
	}

	var subscribedServerInputCommands: [String] {
		["privmsg"]
	}

	func didReceiveServerInput(_ input: PluginServerInput, client: PluginClient) {
		guard client.isConnectedToZNC,
		      client.nickname(input.senderNickname, isZNCUser: "status"),
		      input.messageSequence.hasPrefix("Disconnected from IRC")
		else { return }

		performSynchronouslyOnMainActor {
			self.handleIRCSideDisconnect(client)
		}
	}

	func userInputCommandInvoked(_ invocation: PluginCommandInvocation) {
		Task { @MainActor [weak self] in
			self?.handleUserCommand(invocation)
		}
	}

	@MainActor
	private func handleUserCommand(_ invocation: PluginCommandInvocation) {
		let client = invocation.client
		guard client.isConnectedToZNC else {
			client.printDebug(String(localized: .BasicLanguage.zncConnectionRequired))
			return
		}

		switch invocation.command.uppercased() {
		case "ZNCCERT":
			showCertificateChain(for: client)
		case "DETACH", "ATTACH":
			updateAttachment(
				command: invocation.command.uppercased(),
				message: invocation.message,
				client: client,
				selectedChannel: invocation.selectedChannel
			)
		default:
			break
		}
	}

	@MainActor
	private func showCertificateChain(for client: PluginClient) {
		guard let certificateData = client.zncCertificateChainData else {
			client.printDebug(String(localized: .BasicLanguage.noInformationAvailable))
			return
		}

		var parameters = SecItemImportExportKeyParameters()
		parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
		parameters.flags = []
		var format = SecExternalFormat.formatPEMSequence
		var type = SecExternalItemType.itemTypeCertificate
		var importedItems: CFArray?
		let status = SecItemImport(
			certificateData as CFData,
			nil,
			&format,
			&type,
			[],
			&parameters,
			nil,
			&importedItems
		)

		guard status == errSecSuccess, let certificates = importedItems as? [SecCertificate] else {
			client.printDebug(String(localized: .BasicLanguage.certificateConversionError))
			return
		}

		let panel = SFCertificateTrustPanel()
		panel.setDefaultButtonTitle(String(localized: .BasicLanguage.closeButton))
		panel.setAlternateButtonTitle(nil)
		panel.beginSheet(
			for: NSApp.mainWindow,
			modalDelegate: nil,
			didEnd: nil,
			contextInfo: nil,
			certificates: certificates,
			showGroup: true
		)
	}

	@MainActor
	private func updateAttachment(
		command: String,
		message: String,
		client: PluginClient,
		selectedChannel: PluginChannel?
	) {
		let channelName = message.trimmingCharacters(in: .whitespacesAndNewlines)
		let channel = client.isChannelName(channelName) ? client.channel(named: channelName) : selectedChannel
		guard let channel else { return }

		let isAttach = command == "ATTACH"
		channel.autoJoin = isAttach
		if isAttach {
			client.joinChannel(named: channel.name)
		} else {
			client.sendLine("\(command) \(channel.name)")
			client.printDebug(String(localized: .BasicLanguage.detachConfirmation(channel.name)), in: channel)
		}
	}

	func interceptServerInput(_ input: PluginServerMessage, client: PluginClient) -> PluginServerMessage? {
		guard input.parameters.count == 2, client.isConnectedToZNC, input.command == "PRIVMSG" else { return input }
		let sender = input.sender.nickname
		if client.nickname(sender, isZNCUser: "buffextras") {
			return interceptBufferExtras(input, client: client)
		}
		if client.nickname(sender, isZNCUser: "playback") {
			return interceptPlayback(input, client: client)
		}
		return input
	}

	private func interceptPlayback(_ input: PluginServerMessage, client: PluginClient) -> PluginServerMessage? {
		guard client.isCapabilityEnabled(rawValue: PluginHost.zncPlaybackCapabilityRawValue) else { return input }
		let message = input.parameters[1]
		if message.hasPrefix("The playback buffer for ["),
		   message.contains("] channels matching ["),
		   message.hasSuffix("] has been cleared.")
		{
			return nil
		}
		return input
	}

	private func interceptBufferExtras(_ input: PluginServerMessage, client: PluginClient) -> PluginServerMessage? {
		var parameters = input.parameters
		let message = NSMutableString(string: (parameters[1] as NSString).ceNormalizeSpaces)
		let hostmask = message.ceToken
		guard hostmask.isEmpty == false else { return input }

		var sender = input.sender
		if let components = IRCHostmask(
			parsing: hostmask,
			maximumNicknameLength: Int(client.maximumNicknameLength)
		) {
			guard components.nickname != client.userNickname else { return nil }
			sender.nickname = components.nickname
			sender.username = components.username
			sender.address = components.address
			sender.isServer = false
		} else {
			sender.nickname = hostmask
			sender.isServer = true
		}
		sender.hostmask = hostmask

		let mutableInput = input.copy()
		let body = message as String
		if body == "joined" {
			mutableInput.command = "JOIN"
			parameters.remove(at: 1)
		} else if let captures = captures(in: body, pattern: #"^is now known as ([^\s]+)$"#) {
			mutableInput.command = "NICK"
			parameters.remove(at: 1)
			parameters.append(captures[0])
		} else if let captures = captures(in: body, pattern: #"^(?:parted with message: \[(.*)\]|parted: (.*))$"#) {
			mutableInput.command = "PART"
			parameters.remove(at: 1)
			parameters.append(captures.first(where: { $0.isEmpty == false }) ?? "")
		} else if let captures = captures(in: body, pattern: #"^(?:quit with message: \[(.*)\]|quit: (.*))$"#) {
			mutableInput.command = "QUIT"
			parameters.remove(at: 1)
			parameters.append(captures.first(where: { $0.isEmpty == false }) ?? "")
		} else if let captures = captures(
			in: body,
			pattern: #"^(?:kicked ([^\s]+) with reason: (.*)|kicked ([^\s]+) Reason: \[(.*)\])$"#
		) {
			mutableInput.command = "KICK"
			parameters.remove(at: 1)
			let values = captures.filter { $0.isEmpty == false }
			parameters.append(contentsOf: values.prefix(2))
		} else if let captures = captures(in: body, pattern: #"^set mode: ([^\s]+)( .*)?$"#) {
			mutableInput.command = "MODE"
			parameters.remove(at: 1)
			parameters.append(captures.joined())
		} else if body.hasPrefix("changed the topic to: ") {
			return nil
		}

		mutableInput.isPrintOnlyMessage = true
		mutableInput.parameters = parameters
		mutableInput.sender = sender
		return mutableInput
	}

	private func captures(in string: String, pattern: String) -> [String]? {
		guard let expression = try? NSRegularExpression(pattern: pattern),
		      let match = expression.firstMatch(in: string, range: NSRange(string.startIndex..., in: string))
		else { return nil }
		return (1 ..< match.numberOfRanges).map { index in
			let range = match.range(at: index)
			guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return "" }
			return String(string[swiftRange])
		}
	}

	@MainActor
	private func handleIRCSideDisconnect(_ client: PluginClient) {
		for channel in client.channels where channel.isActive && channel.name.hasPrefix("~#") == false {
			channel.deactivate()
		}
		client.refreshSidebar()
	}
}

private func performSynchronouslyOnMainActor(_ work: @MainActor @Sendable () -> Void) {
	if Thread.isMainThread {
		MainActor.assumeIsolated {
			work()
		}
	} else {
		DispatchQueue.main.sync {
			MainActor.assumeIsolated {
				work()
			}
		}
	}
}
