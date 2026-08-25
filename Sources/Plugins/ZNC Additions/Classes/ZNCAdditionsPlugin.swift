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
import Security
import SecurityInterface

@objc(TPI_ZNCAdditions)
final class ZNCAdditionsPlugin: NSObject, THOPluginProtocol, @unchecked Sendable {
	private var bundle: Bundle {
		Bundle(for: ZNCAdditionsPlugin.self)
	}

	var subscribedUserInputCommands: [String] {
		["detach", "attach", "znccert"]
	}

	var subscribedServerInputCommands: [String] {
		["privmsg"]
	}

	func didReceiveServerInput(_ input: THOPluginDidReceiveServerInputConcreteObject, on client: IRCClient) {
		guard client.isConnectedToZNC,
		      client.nickname(input.senderNickname, isZNCUser: "status"),
		      input.messageSequence.hasPrefix("Disconnected from IRC")
		else { return }

		let client = MainActorTransfer(value: client)
		performSynchronouslyOnMainActor {
			self.handleIRCSideDisconnect(client.value)
		}
	}

	func userInputCommandInvoked(on client: IRCClient, command: String, messageString: String) {
		let client = MainActorTransfer(value: client)
		Task { @MainActor [weak self] in
			self?.handleUserCommand(command, message: messageString, client: client.value)
		}
	}

	@MainActor
	private func handleUserCommand(_ command: String, message: String, client: IRCClient) {
		guard client.isConnectedToZNC else {
			client.printDebugInformation(localized("xex-nl"))
			return
		}

		switch command.uppercased() {
		case "ZNCCERT":
			showCertificateChain(for: client)
		case "DETACH", "ATTACH":
			updateAttachment(command: command.uppercased(), message: message, client: client)
		default:
			break
		}
	}

	@MainActor
	private func showCertificateChain(for client: IRCClient) {
		guard let certificateData = client.zncBouncerCertificateChainData else {
			client.printDebugInformation(localized("moh-hg"))
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
			client.printDebugInformation(localized("wco-zv"))
			return
		}

		let panel = SFCertificateTrustPanel()
		panel.setDefaultButtonTitle(NSLocalizedString("Prompts[aqw-q1]", comment: ""))
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
	private func updateAttachment(command: String, message: String, client: IRCClient) {
		let channelName = message.trimmingCharacters(in: .whitespacesAndNewlines)
		let channel = client.stringIsChannelName(channelName)
			? client.findChannel(channelName)
			: NSObject.masterController().mainWindow.selectedChannel
		guard let channel else { return }

		let isAttach = command == "ATTACH"
		channel.autoJoin = isAttach
		if isAttach {
			client.joinUnlistedChannel(channel.name)
		} else {
			client.sendLine("\(command) \(channel.name)")
			client.printDebugInformation(localized("0fr-kb", channel.name), in: channel)
		}
	}

	func interceptServerInput(_ input: IRCMessage, for client: IRCClient) -> IRCMessage? {
		guard input.paramsCount == 2, client.isConnectedToZNC, input.command == "PRIVMSG" else { return input }
		let sender = input.sender.nickname
		if client.nickname(sender, isZNCUser: "buffextras") {
			return interceptBufferExtras(input, client: client)
		}
		if client.nickname(sender, isZNCUser: "playback") {
			return interceptPlayback(input, client: client)
		}
		return input
	}

	private func interceptPlayback(_ input: IRCMessage, client: IRCClient) -> IRCMessage? {
		let playbackCapability = ClientIRCv3SupportedCapability(
			rawValue: UInt(ClientIRCv3SupportedCapabilityZNCPlaybackModule)
		)
		guard client.isCapabilityEnabled(playbackCapability) else { return input }
		let message = input.param(at: 1)
		if message.hasPrefix("The playback buffer for ["),
		   message.contains("] channels matching ["),
		   message.hasSuffix("] has been cleared.")
		{
			return nil
		}
		return input
	}

	private func interceptBufferExtras(_ input: IRCMessage, client: IRCClient) -> IRCMessage? {
		var parameters = input.params
		let message = NSMutableString(string: (parameters[1] as NSString).normalizeSpaces)
		let hostmask = message.token
		guard hostmask.isEmpty == false else { return input }

		let sender = input.sender.mutableCopy() as! IRCPrefixMutable
		var nickname: NSString?
		var username: NSString?
		var address: NSString?
		if (hostmask as NSString).hostmaskComponents(&nickname, username: &username, address: &address, on: client) {
			guard nickname as String? != client.userNickname else { return nil }
			sender.nickname = nickname as String? ?? ""
			sender.username = username as String?
			sender.address = address as String?
			sender.isServer = false
		} else {
			sender.nickname = hostmask
			sender.isServer = true
		}
		sender.hostmask = hostmask

		let mutableInput = input.mutableCopy() as! IRCMessageMutable
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
		mutableInput.params = parameters
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
	private func handleIRCSideDisconnect(_ client: IRCClient) {
		for channel in client.channelList where channel.isActive && channel.name.hasPrefix("~#") == false {
			channel.deactivate()
		}
		NSObject.masterController().mainWindow.reloadTreeGroup(client)
	}

	private func localized(_ key: String, _ arguments: CVarArg...) -> String {
		let format = bundle.localizedString(forKey: key, value: nil, table: "BasicLanguage")
		return arguments.isEmpty ? format : String(format: format, arguments: arguments)
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

private struct MainActorTransfer<Value>: @unchecked Sendable {
	let value: Value
}
