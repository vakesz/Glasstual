/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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

import CocoaExtensions
import Foundation

struct ParsedUserCommand {
	let command: String
	let arguments: NSMutableAttributedString

	init?(_ input: Any) {
		let source: NSAttributedString
		if let string = input as? String {
			source = NSAttributedString(string: string)
		} else if let attributed = input as? NSAttributedString {
			source = attributed
		} else {
			assertionFailure("Command input must be String or NSAttributedString")
			return nil
		}

		guard source.length > 0 else { return nil }
		arguments = NSMutableAttributedString(attributedString: source)
		if arguments.string.hasPrefix("/") {
			arguments.deleteCharacters(in: NSRange(location: 0, length: 1))
		}
		command = arguments.nextTokenAsString()
	}
}

@MainActor
public extension IRCClient {
	@objc(sendCommand:)
	func sendCommand(_ input: Any) {
		sendCommand(input, completeTarget: true, target: nil)
	}

	@objc(sendCommand:completeTarget:target:)
	func sendCommand(_ input: Any, completeTarget: Bool, target targetChannelName: String?) {
		guard let parsed = ParsedUserCommand(input) else { return }
		let targetChannel = resolvedTargetChannel(
			completeTarget: completeTarget,
			targetChannelName: targetChannelName
		)
		if dispatchDCCCommand(parsed, targetChannel: targetChannel) ||
			dispatchMessageCommand(parsed, targetChannel: targetChannel) ||
			dispatchDefaultsCommand(parsed) ||
			dispatchIgnoreCommand(parsed, targetChannel: targetChannel) ||
			dispatchTimerCommand(parsed, targetChannel: targetChannel) ||
			dispatchNativeChannelCommand(parsed, targetChannel: targetChannel) ||
			dispatchNativeCommand(parsed, targetChannel: targetChannel)
		{
			return
		}
		dispatchAddonOrRawCommand(parsed, targetChannel: targetChannel)
	}

	private func dispatchAddonOrRawCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) {
		let lowercaseCommand = parsed.command.lowercased()
		var addonPath: NSString?
		var scriptFound = ObjCBool(false)
		var pluginFound = ObjCBool(false)
		SharedApplication.sharedPluginManager().findHandler(
			forOutgoingCommand: lowercaseCommand,
			path: &addonPath,
			isScript: &scriptFound,
			isExtension: &pluginFound
		)

		if pluginFound.boolValue, scriptFound.boolValue {
			printDebugInformation(IRCCommandStrings.pluginAndScriptConflict(command: parsed.command.uppercased()))
		} else if pluginFound.boolValue {
			processBundlesUserMessage(parsed.arguments.string, command: lowercaseCommand)
		} else if scriptFound.boolValue, let addonPath {
			var context = [
				"inputString": parsed.arguments.string,
				"path": addonPath as String,
			]
			if let targetChannel {
				context["targetChannel"] = targetChannel.name
			}
			executeGlasstualCmdScript(inContext: context)
		} else {
			sendCommand(parsed.command.uppercased(), withData: parsed.arguments.string)
		}
	}

	private func dispatchDCCCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		guard parsed.command.caseInsensitiveCompare("dcc") == .orderedSame else { return false }
		handleDCCCommand(
			NSMutableAttributedString(attributedString: parsed.arguments),
			command: parsed.command,
			targetChannel: targetChannel
		)
		return true
	}

	private func dispatchNativeCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		let command = parsed.command.lowercased()
		let arguments = parsed.arguments.string

		switch command {
		case "aquote", "araw":
			guard isConnected else { return true }
			guard requireArguments(arguments, for: parsed.command) else { return true }
			for client in currentClients() {
				client.sendLine(arguments)
			}

		case "quote", "raw":
			guard isConnected else { return true }
			guard requireArguments(arguments, for: parsed.command) else { return true }
			sendLine(arguments)

		case "cap", "caps":
			let capabilities = enabledCapabilitiesStringValue
			printDebugInformation(
				capabilities.isEmpty
					? IRCCommandStrings.noEnabledCapabilities
					: IRCCommandStrings.enabledCapabilities(capabilities)
			)

		case "debug", "echo":
			guard requireArguments(arguments, for: parsed.command) else { return true }
			if arguments.caseInsensitiveCompare("raw on") == .orderedSame {
				createRawDataLogQuery()
			} else if arguments.caseInsensitiveCompare("raw off") == .orderedSame {
				destroyRawDataLogQuery()
			} else {
				printDebugInformation(arguments)
			}

		default:
			return dispatchNativeRequestCommand(parsed, targetChannel: targetChannel)
		}
		return true
	}

	private func dispatchNativeRequestCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		let command = parsed.command.lowercased()
		let arguments = parsed.arguments.string
		switch command {
		case "ison":
			guard isLoggedIn else { return true }
			guard requireArguments(arguments, for: parsed.command) else { return true }
			createHiddenCommandResponses()
			requestedCommands.recordIsonRequestOpenedAsVisible()
			send("ISON", arguments: [arguments])

		case "names":
			guard isLoggedIn else { return true }
			guard requireArguments(arguments, for: parsed.command) else { return true }
			createHiddenCommandResponses()
			send("NAMES", arguments: [arguments])

		case "recv":
			guard requireDeveloperMode() else { return true }
			guard requireArguments(arguments, for: parsed.command) else { return true }
			guard let socket else { return true }
			ircConnection(socket, didReceiveData: arguments)

		case "setname":
			guard isLoggedIn else { return true }
			guard requireArguments(arguments, for: parsed.command) else { return true }
			guard isCapabilityEnabled(.setName) else {
				printDebugInformation(IRCCommandStrings.setNameUnsupported)
				return true
			}
			send("SETNAME", arguments: [arguments])

		case "wallops":
			guard isLoggedIn else { return true }
			guard requireArguments(arguments, for: parsed.command) else { return true }
			send("WALLOPS", arguments: [arguments])

		default:
			return dispatchNativeOperatorCommand(parsed, targetChannel: targetChannel)
		}
		return true
	}

	private func dispatchNativeOperatorCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		switch parsed.command.lowercased() {
		case "gline", "gzline", "shun", "tempshun", "zline":
			guard isLoggedIn else { return true }
			let mutableArguments = NSMutableAttributedString(attributedString: parsed.arguments)
			let firstSegment = mutableArguments.nextTokenAsString()
			let secondSegment = mutableArguments.nextTokenAsString()
			send(
				parsed.command.uppercased(),
				arguments: [firstSegment, secondSegment, mutableArguments.string]
			)

		case "kill":
			guard isLoggedIn else { return true }
			let mutableArguments = NSMutableAttributedString(attributedString: parsed.arguments)
			let nickname = mutableArguments.nextTokenAsString()
			guard requireArguments(nickname, for: parsed.command) else { return true }
			let reason = mutableArguments.string.isEmpty
				? TextualPreferences.irCopDefaultKillMessage()
				: mutableArguments.string
			send("KILL", arguments: [nickname, reason])

		default:
			return dispatchNativeSessionCommand(parsed, targetChannel: targetChannel)
		}
		return true
	}

	private func dispatchNativeSessionCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		let command = parsed.command.lowercased()
		let arguments = parsed.arguments.string
		switch command {
		case "conn":
			let mutableArguments = NSMutableAttributedString(attributedString: parsed.arguments)
			let serverAddress = mutableArguments.nextTokenAsString().lowercased()
			if serverAddress.isEmpty == false {
				guard (serverAddress as NSString).isValidInternetAddress else {
					printDebugInformation(IRCCommandStrings.invalidArguments)
					return true
				}
				temporaryServerAddressOverride = serverAddress
			}
			if isConnecting || isConnected {
				addDisconnectCallback { [weak self] in self?.connect() }
				quit()
			} else {
				connect()
			}

		case "back":
			guard isLoggedIn else { return true }
			for client in currentClients() where client === self || TextualPreferences.awayAllConnections() {
				client.toggleAwayStatus(false, withComment: nil)
			}

		case "away":
			guard isLoggedIn else { return true }
			for client in currentClients() where client === self || TextualPreferences.awayAllConnections() {
				let maximumLength = Int(client.supportInfo.maximumAwayLength)
				let comment = ClientWireUtilities.truncated(arguments, toByteCount: maximumLength)
				if comment != arguments {
					client.printDebugInformation(
						IRCCommandStrings.awayMessageTooLong(
							networkName: networkNameAlt,
							maximumLength: maximumLength
						)
					)
				}
				client.toggleAwayStatus(true, withComment: comment)
			}

		case "autojoin":
			guard isLoggedIn else { return true }
			performAutoJoin(initiatedByUser: true)

		case "nick":
			guard isConnected else { return true }
			let mutableArguments = NSMutableAttributedString(string: arguments)
			let nickname = mutableArguments.nextTokenAsString()
			guard requireArguments(nickname, for: parsed.command) else { return true }
			for client in currentClients() where client === self || TextualPreferences.nickAllConnections() {
				client.changeNickname(nickname)
			}

		default:
			return dispatchNativeNotificationAndConnectionCommand(parsed, targetChannel: targetChannel)
		}
		return true
	}

	private func dispatchNativeNotificationAndConnectionCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		let command = parsed.command.lowercased()
		let arguments = parsed.arguments.string
		switch command {
		case "mute":
			if TextualPreferences.soundIsMuted() {
				printDebugInformation(IRCCommandStrings.soundAlreadyMuted)
			} else {
				printDebugInformation(IRCCommandStrings.soundMuted)
				AppController.shared.menuController?.toggleMuteOnNotificationSoundsShortcut(on: true)
			}

		case "unmute":
			if TextualPreferences.soundIsMuted() == false {
				printDebugInformation(IRCCommandStrings.soundNotMuted)
			} else {
				printDebugInformation(IRCCommandStrings.soundUnmuted)
				AppController.shared.menuController?.toggleMuteOnNotificationSoundsShortcut(on: false)
			}

		case "notifybubble":
			let mutableArguments = NSMutableAttributedString(attributedString: parsed.arguments)
			let notificationChannel = stringIsChannelName(mutableArguments.string)
				? findChannel(mutableArguments.nextTokenAsString())
				: nil
			guard requireArguments(mutableArguments.string, for: parsed.command) else { return true }
			SharedApplication.sharedNotificationController().scheduleNotification(
				title: ApplicationInfo.applicationNameWithoutVersion(),
				message: mutableArguments.string,
				for: notificationChannel,
				on: self
			)

		case "notifysound":
			let mutableArguments = NSMutableAttributedString(string: arguments)
			let sound = mutableArguments.nextTokenAsString()
			guard requireArguments(sound, for: parsed.command) else { return true }
			SoundPlayer.playAlertSound(sound)

		case "notifyspeak":
			guard requireArguments(arguments, for: parsed.command) else { return true }
			SharedApplication.sharedSpeechSynthesizer().speak(text: arguments)

		case "quit":
			guard isConnected else { return true }
			if arguments.isEmpty {
				quit()
			} else {
				quit(withComment: arguments)
			}

		case "server":
			guard requireArguments(arguments, for: parsed.command) else { return true }
			Extras.createConnectionToServer(arguments, channelList: nil, connectWhenCreated: true)

		case "sslcontext":
			presentCertificateTrustInformation()

		default:
			return dispatchNativeCapabilityCommand(parsed, targetChannel: targetChannel)
		}
		return true
	}

	private func dispatchNativeCapabilityCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		let command = parsed.command.lowercased()
		let arguments = parsed.arguments.string
		switch command {
		case "chathistory":
			guard isLoggedIn else { return true }
			guard requireArguments(arguments, for: parsed.command) else { return true }
			guard isCapabilityEnabled(.chatHistory) else {
				printDebugInformation(IRCCommandStrings.chatHistoryUnsupported)
				return true
			}
			sendLine("CHATHISTORY \(arguments)")

		case "umode":
			guard isLoggedIn else { return true }
			var parameters = [userNickname]
			if arguments.isEmpty == false {
				parameters.append(arguments)
			}
			send("MODE", arguments: parameters)

		case "monitor", "watch":
			guard isLoggedIn else { return true }
			guard requireArguments(arguments, for: parsed.command) else { return true }
			let components = arguments.components(separatedBy: .whitespaces)
			if components.contains(where: { $0.hasPrefix("-") || $0.hasPrefix("+") }) {
				printDebugInformation(IRCCommandStrings.useAddressBookForTrackedUsers)
				return true
			}
			if components.contains(where: { $0.caseInsensitiveCompare("c") == .orderedSame }) == false {
				createHiddenCommandResponses()
			}
			sendCommand(parsed.command.uppercased(), withData: arguments)

		case "silence":
			guard isLoggedIn else { return true }
			guard supportInfo.silenceSupported else {
				printDebugInformation(IRCCommandStrings.silenceUnsupported)
				return true
			}
			sendCommand(parsed.command.uppercased(), withData: arguments)

		default:
			return dispatchNativeInformationCommand(parsed, targetChannel: targetChannel)
		}
		return true
	}

	private func dispatchNativeInformationCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		if dispatchLagCommand(parsed) {
			return true
		}
		let command = parsed.command.lowercased()
		let arguments = parsed.arguments.string
		switch command {
		case "who":
			guard isLoggedIn else { return true }
			guard requireArguments(arguments, for: parsed.command) else { return true }
			createHiddenCommandResponses()
			requestedCommands.recordWhoRequestOpenedAsVisible()
			send("WHO", arguments: [arguments])

		case "whois":
			guard isLoggedIn else { return true }
			let mutableArguments = NSMutableAttributedString(string: arguments)
			var firstNickname = mutableArguments.nextTokenAsString()
			if firstNickname.isEmpty, let targetChannel, targetChannel.isPrivateMessage {
				firstNickname = targetChannel.name
			}
			guard requireArguments(firstNickname, for: parsed.command) else { return true }
			let secondNickname = mutableArguments.nextTokenAsString()
			if secondNickname.isEmpty {
				send("WHOIS", arguments: [firstNickname, firstNickname])
			} else {
				send("WHOIS", arguments: [firstNickname, secondNickname])
			}

		case "weights":
			guard let targetChannel, targetChannel.isChannel else {
				printDebugInformation(IRCCommandStrings.channelRequired)
				return true
			}
			printDebugInformation(IRCCommandStrings.nicknameWeights(channelName: targetChannel.name))
			var hasWeights = false
			for member in targetChannel.memberList ?? [] {
				let incomingWeight = member.incomingWeight
				let outgoingWeight = member.outgoingWeight
				let combinedWeight = incomingWeight + outgoingWeight
				guard combinedWeight > 0 else { continue }
				hasWeights = true
				printDebugInformation(
					IRCCommandStrings.nicknameWeight(
						member.user.nickname,
						sent: outgoingWeight,
						received: incomingWeight,
						total: combinedWeight
					)
				)
			}
			if hasWeights == false {
				printDebugInformation(IRCCommandStrings.noNicknameWeights)
			}

		case "myversion":
			let applicationName = ApplicationInfo.applicationNameWithoutVersion()
			let versionLong = ApplicationInfo.applicationVersion()
			let versionShort = ApplicationInfo.applicationVersionShort()
			let buildType = IRCCommandStrings.classicBinaryArchitecture(IRCCommandStrings.appleSilicon)
			var message = IRCCommandStrings.version(
				applicationName: applicationName,
				shortVersion: versionShort,
				buildVersion: versionLong,
				buildSuffix: "",
				buildType: buildType
			)
			if let targetChannel {
				message = IRCCommandStrings.sharingVersion(message)
				sendPrivmsg(message, to: targetChannel)
			} else {
				printDebugInformation(toConsole: message)
			}

		case "tage":
			let elapsed = Date().timeIntervalSince1970 - ApplicationInfo.applicationBirthday()
			let readableElapsed = humanReadableTimeInterval(elapsed, false, 0) as String? ?? ""
			let message = IRCCommandStrings.timeSinceFirstCommit(readableElapsed)
			if let targetChannel {
				sendPrivmsg(message, to: targetChannel)
			} else {
				printDebugInformation(toConsole: message)
			}

		default:
			return false
		}

		return true
	}

	private func dispatchLagCommand(_ parsed: ParsedUserCommand) -> Bool {
		let command = parsed.command.lowercased()
		guard command == "lagcheck" || command == "mylag" else { return false }
		guard isLoggedIn, let socket else { return true }
		var context: [String: Any] = [
			"connection": socket.uniqueIdentifier,
			"time": Date().timeIntervalSince1970,
		]
		if command == "mylag",
		   let channel = AppController.shared.mainWindow.selectedChannel(on: self)
		{
			context["channel"] = channel.name
		}
		var components = URLComponents()
		components.queryItems = context.map { key, value in
			URLQueryItem(name: key, value: String(describing: value))
		}
		let payload = components.percentEncodedQuery ?? ""
		sendCTCPQuery(userNickname, command: "LAGCHECK", text: payload)
		printDebugInformation(IRCCommandStrings.waitingForLagCheck)
		return true
	}

	func requireArguments(_ arguments: String, for command: String) -> Bool {
		guard arguments.isEmpty else { return true }
		printInvalidSyntaxMessage(for: command)
		return false
	}

	/// Gates a command that is marked `developerModeOnly` in the command
	/// index. The index itself is only consulted for the completion list, so
	/// developer-only commands are otherwise reachable by anyone who types
	/// them.
	func requireDeveloperMode() -> Bool {
		guard TextualPreferences.developerModeEnabled() == false else { return true }
		printDebugInformation(IRCCommandStrings.developerModeRequired)
		return false
	}

	private func currentClients() -> [IRCClient] {
		AppController.shared.world.clientList
	}

	private func resolvedTargetChannel(
		completeTarget: Bool,
		targetChannelName: String?
	) -> IRCChannel? {
		guard completeTarget else { return nil }
		if let targetChannelName {
			return findChannel(targetChannelName)
		}
		guard let mainWindow = AppController.shared.mainWindow,
		      mainWindow.selectedClient === self
		else {
			return nil
		}
		return mainWindow.selectedChannel
	}
}
