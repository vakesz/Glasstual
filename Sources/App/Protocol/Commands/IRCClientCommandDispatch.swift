/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
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

@MainActor
public extension IRCClient {
	func sendCommand(_ input: Any) {
		sendCommand(input, completeTarget: true, target: nil)
	}

	func sendCommand(_ input: Any, completeTarget: Bool, target targetChannelName: String?) {
		guard let parsed = ParsedUserCommand(input) else { return }
		guard allowsDeveloperModeCommand(parsed) else { return }
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

	/// Refuses a command the index marks `developerModeOnly` unless the
	/// preference is on. The flag used to reach only the completion list, so
	/// every developer command was still reachable by typing its name; two of
	/// them were then gated again by hand inside their handlers.
	private func allowsDeveloperModeCommand(_ parsed: ParsedUserCommand) -> Bool {
		guard parsed.isDeveloperModeOnly,
		      environment.preferences.developerModeEnabled == false
		else {
			return true
		}
		printDebugInformation(IRCCommandStrings.developerModeRequired)
		return false
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
			processBundlesUserMessage(parsed.arguments.rest, command: lowercaseCommand)
		} else if scriptFound.boolValue, let addonPath {
			var context = [
				"inputString": parsed.arguments.rest,
				"path": addonPath as String,
			]
			if let targetChannel {
				context["targetChannel"] = targetChannel.name
			}
			executeGlasstualCmdScript(inContext: context)
		} else {
			sendCommand(parsed.command.uppercased(), withData: parsed.arguments.rest)
		}
	}

	private func dispatchDCCCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		guard parsed.localCommand == .dcc else { return false }
		handleDCCCommand(parsed.arguments, command: parsed.command, targetChannel: targetChannel)
		return true
	}

	private func dispatchNativeCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		guard let command = parsed.localCommand else { return false }
		let arguments = parsed.arguments.rest

		switch command {
		case .aquote, .araw:
			guard isConnected else { return true }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return true }
			for client in currentClients() {
				client.sendLine(arguments)
			}

		case .quote, .raw:
			guard isConnected else { return true }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return true }
			sendLine(arguments)

		case .cap, .caps:
			let capabilities = enabledCapabilitiesStringValue
			printDebugInformation(
				capabilities.isEmpty
					? IRCCommandStrings.noEnabledCapabilities
					: IRCCommandStrings.enabledCapabilities(capabilities)
			)

		case .debug, .echo:
			guard requireArguments(parsed.arguments, for: parsed.command) else { return true }
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
		guard let command = parsed.localCommand else { return false }
		let arguments = parsed.arguments.rest
		switch command {
		case .ison:
			guard isLoggedIn else { return true }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return true }
			createHiddenCommandResponses()
			requestedCommands.recordIsonRequestOpenedAsVisible()
			send("ISON", arguments: [arguments])

		case .names:
			guard isLoggedIn else { return true }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return true }
			createHiddenCommandResponses()
			send("NAMES", arguments: [arguments])

		case .recv:
			guard requireArguments(parsed.arguments, for: parsed.command) else { return true }
			guard let socket else { return true }
			ircConnection(socket, didReceiveData: arguments)

		case .setname:
			guard isLoggedIn else { return true }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return true }
			guard isCapabilityEnabled(.setName) else {
				printDebugInformation(IRCCommandStrings.setNameUnsupported)
				return true
			}
			send("SETNAME", arguments: [arguments])

		case .wallops:
			guard isLoggedIn else { return true }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return true }
			send("WALLOPS", arguments: [arguments])

		default:
			return dispatchNativeOperatorCommand(parsed, targetChannel: targetChannel)
		}
		return true
	}

	private func dispatchNativeOperatorCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		guard let command = parsed.localCommand else { return false }
		var arguments = parsed.arguments
		switch command {
		case .gline, .gzline, .shun, .tempshun, .zline:
			guard isLoggedIn else { return true }
			let firstSegment = arguments.next()
			let secondSegment = arguments.next()
			send(
				parsed.command.uppercased(),
				arguments: [firstSegment, secondSegment, arguments.rest]
			)

		case .kill:
			guard isLoggedIn else { return true }
			let nickname = arguments.next()
			guard requireArguments(nickname, for: parsed.command) else { return true }
			let reason = arguments.isEmpty
				? environment.preferences.irCopDefaultKillMessage
				: arguments.rest
			send("KILL", arguments: [nickname, reason])

		default:
			return dispatchNativeSessionCommand(parsed, targetChannel: targetChannel)
		}
		return true
	}

	private func dispatchNativeSessionCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		guard let command = parsed.localCommand else { return false }
		var arguments = parsed.arguments
		switch command {
		case .conn:
			let serverAddress = arguments.next().lowercased()
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

		case .back:
			guard isLoggedIn else { return true }
			for client in currentClients() where client === self || environment.preferences.awayAllConnections {
				client.toggleAwayStatus(false, withComment: nil)
			}

		case .away:
			guard isLoggedIn else { return true }
			broadcastAwayStatus(comment: arguments.rest)

		case .autojoin:
			guard isLoggedIn else { return true }
			performAutoJoin(initiatedByUser: true)

		case .nick:
			guard isConnected else { return true }
			let nickname = arguments.next()
			guard requireArguments(nickname, for: parsed.command) else { return true }
			for client in currentClients() where client === self || environment.preferences.nickAllConnections {
				client.changeNickname(nickname)
			}

		default:
			return dispatchNativeNotificationAndConnectionCommand(parsed, targetChannel: targetChannel)
		}
		return true
	}

	private func broadcastAwayStatus(comment: String) {
		for client in currentClients() where client === self || environment.preferences.awayAllConnections {
			let maximumLength = Int(client.supportInfo.maximumAwayLength)
			let truncated = ClientWireUtilities.truncated(comment, toByteCount: maximumLength)
			if truncated != comment {
				client.printDebugInformation(
					IRCCommandStrings.awayMessageTooLong(
						networkName: networkNameAlt,
						maximumLength: maximumLength
					)
				)
			}
			client.toggleAwayStatus(true, withComment: truncated)
		}
	}

	private func dispatchNativeNotificationAndConnectionCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		guard let command = parsed.localCommand else { return false }
		var arguments = parsed.arguments
		switch command {
		case .mute:
			toggleNotificationSoundMute(true)

		case .unmute:
			toggleNotificationSoundMute(false)

		case .notifybubble:
			let notificationChannel = stringIsChannelName(arguments.rest)
				? findChannel(arguments.next())
				: nil
			guard requireArguments(arguments, for: parsed.command) else { return true }
			SharedApplication.sharedNotificationController().scheduleNotification(
				title: ApplicationInfo.applicationNameWithoutVersion(),
				message: arguments.rest,
				for: notificationChannel,
				on: self
			)

		case .notifysound:
			let sound = arguments.next()
			guard requireArguments(sound, for: parsed.command) else { return true }
			SoundPlayer.playAlertSound(sound)

		case .notifyspeak:
			guard requireArguments(arguments, for: parsed.command) else { return true }
			SharedApplication.sharedSpeechSynthesizer().speak(text: arguments.rest)

		case .quit:
			guard isConnected else { return true }
			if arguments.isEmpty {
				quit()
			} else {
				quit(withComment: arguments.rest)
			}

		case .server:
			guard requireArguments(arguments, for: parsed.command) else { return true }
			Extras.createConnectionToServer(arguments.rest, channelList: nil, connectWhenCreated: true)

		case .sslcontext:
			presentCertificateTrustInformation()

		default:
			return dispatchNativeCapabilityCommand(parsed, targetChannel: targetChannel)
		}
		return true
	}

	private func toggleNotificationSoundMute(_ muted: Bool) {
		let alreadyInState = environment.preferences.soundIsMuted == muted
		guard alreadyInState == false else {
			printDebugInformation(muted ? IRCCommandStrings.soundAlreadyMuted : IRCCommandStrings.soundNotMuted)
			return
		}
		printDebugInformation(muted ? IRCCommandStrings.soundMuted : IRCCommandStrings.soundUnmuted)
		menu?.toggleMuteOnNotificationSoundsShortcut(on: muted)
	}

	private func dispatchNativeCapabilityCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		guard let command = parsed.localCommand else { return false }
		let arguments = parsed.arguments.rest
		switch command {
		case .chathistory:
			guard isLoggedIn else { return true }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return true }
			guard isCapabilityEnabled(.chatHistory) else {
				printDebugInformation(IRCCommandStrings.chatHistoryUnsupported)
				return true
			}
			sendLine("CHATHISTORY \(arguments)")

		case .umode:
			guard isLoggedIn else { return true }
			var parameters = [userNickname]
			if arguments.isEmpty == false {
				parameters.append(arguments)
			}
			send("MODE", arguments: parameters)

		case .monitor, .watch:
			guard isLoggedIn else { return true }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return true }
			let components = arguments.components(separatedBy: .whitespaces)
			if components.contains(where: { $0.hasPrefix("-") || $0.hasPrefix("+") }) {
				printDebugInformation(IRCCommandStrings.useAddressBookForTrackedUsers)
				return true
			}
			if components.contains(where: { $0.caseInsensitiveCompare("c") == .orderedSame }) == false {
				createHiddenCommandResponses()
			}
			sendCommand(parsed.command.uppercased(), withData: arguments)

		case .silence:
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
		guard let command = parsed.localCommand else { return false }
		var arguments = parsed.arguments
		switch command {
		case .who:
			guard isLoggedIn else { return true }
			guard requireArguments(arguments, for: parsed.command) else { return true }
			createHiddenCommandResponses()
			requestedCommands.recordWhoRequestOpenedAsVisible()
			send("WHO", arguments: [arguments.rest])

		case .whois:
			guard isLoggedIn else { return true }
			var firstNickname = arguments.next()
			if firstNickname.isEmpty, let targetChannel, targetChannel.isPrivateMessage {
				firstNickname = targetChannel.name
			}
			guard requireArguments(firstNickname, for: parsed.command) else { return true }
			let secondNickname = arguments.next()
			send("WHOIS", arguments: [firstNickname, secondNickname.isEmpty ? firstNickname : secondNickname])

		case .weights:
			printNicknameWeights(in: targetChannel)

		case .myversion:
			printApplicationVersion(to: targetChannel)

		case .tage:
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

	private func printNicknameWeights(in targetChannel: IRCChannel?) {
		guard let targetChannel, targetChannel.isChannel else {
			printDebugInformation(IRCCommandStrings.channelRequired)
			return
		}
		printDebugInformation(IRCCommandStrings.nicknameWeights(channelName: targetChannel.name))
		var hasWeights = false
		for member in targetChannel.memberList {
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
	}

	private func printApplicationVersion(to targetChannel: IRCChannel?) {
		let buildType = IRCCommandStrings.classicBinaryArchitecture(IRCCommandStrings.appleSilicon)
		var message = IRCCommandStrings.version(
			applicationName: ApplicationInfo.applicationNameWithoutVersion(),
			shortVersion: ApplicationInfo.applicationVersionShort(),
			buildVersion: ApplicationInfo.applicationVersion(),
			buildSuffix: "",
			buildType: buildType
		)
		if let targetChannel {
			message = IRCCommandStrings.sharingVersion(message)
			sendPrivmsg(message, to: targetChannel)
		} else {
			printDebugInformation(toConsole: message)
		}
	}

	private func dispatchLagCommand(_ parsed: ParsedUserCommand) -> Bool {
		guard let command = parsed.localCommand, command == .lagcheck || command == .mylag else { return false }
		guard isLoggedIn, let socket else { return true }
		var queryItems = [
			URLQueryItem(name: "connection", value: socket.uniqueIdentifier),
			URLQueryItem(name: "time", value: String(Date().timeIntervalSince1970)),
		]
		if command == .mylag,
		   let channel = output?.selectedChannel(on: self)
		{
			queryItems.append(URLQueryItem(name: "channel", value: channel.name))
		}
		var components = URLComponents()
		components.queryItems = queryItems
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

	/// Rejects a command line that carries fewer arguments than the command
	/// index declares required, printing the index's own syntax line.
	func requireArguments(_ arguments: CommandArguments, for command: String) -> Bool {
		guard arguments.satisfiesDeclaredArity == false else { return true }
		printInvalidSyntaxMessage(for: command)
		return false
	}

	private func currentClients() -> [IRCClient] {
		(world?.clientList ?? [])
	}

	private func resolvedTargetChannel(
		completeTarget: Bool,
		targetChannelName: String?
	) -> IRCChannel? {
		guard completeTarget else { return nil }
		if let targetChannelName {
			return findChannel(targetChannelName)
		}
		guard let output, output.selectedClient === self else {
			return nil
		}
		return output.selectedChannel
	}
}
