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
	func sendCommand(_ input: Any, completeTarget: Bool = true, target targetChannelName: String? = nil) {
		guard let parsed = ParsedUserCommand(input) else { return }
		guard allowsDeveloperModeCommand(parsed) else { return }

		let targetChannel = resolvedTargetChannel(
			completeTarget: completeTarget,
			targetChannelName: targetChannelName
		)

		/* A name the client has no handler for is not an error: it belongs to a
		 plugin, a script, or the server. */
		guard let group = parsed.localCommand?.group else {
			dispatchAddonOrRawCommand(parsed, targetChannel: targetChannel)

			return
		}

		switch group {
		case .directChat:
			handleDCCCommand(parsed.arguments, command: parsed.command, targetChannel: targetChannel)
		case .message:
			dispatchMessageCommand(parsed, targetChannel: targetChannel)
		case .defaults:
			dispatchDefaultsCommand(parsed)
		case .ignore:
			dispatchIgnoreCommand(parsed, targetChannel: targetChannel)
		case .timer:
			dispatchTimerCommand(parsed, targetChannel: targetChannel)
		case let .channel(channelGroup):
			dispatchNativeChannelCommand(channelGroup, parsed: parsed, targetChannel: targetChannel)
		case let .native(nativeGroup):
			dispatchNativeCommand(nativeGroup, parsed: parsed, targetChannel: targetChannel)
		}
	}

	/// Refuses a developer-mode command unless the preference is on. Keeping
	/// the flag out of the completion list is not enough on its own: the name
	/// still works when typed.
	private func allowsDeveloperModeCommand(_ parsed: ParsedUserCommand) -> Bool {
		guard parsed.isDeveloperModeOnly,
		      environment.preferences.developerModeEnabled == false
		else {
			return true
		}
		printDebugInformation(IRCCommandStrings.developerModeRequired)
		return false
	}

	private func dispatchAddonOrRawCommand(_ parsed: ParsedUserCommand, targetChannel: Channel?) {
		let lowercaseCommand = parsed.command.lowercased()

		switch SharedApplication.sharedPluginManager().handler(forOutgoingCommand: lowercaseCommand) {
		case .ambiguous:
			printDebugInformation(IRCCommandStrings.pluginAndScriptConflict(command: parsed.command.uppercased()))
		case .pluginExtension:
			processBundlesUserMessage(parsed.arguments.rest, command: lowercaseCommand)
		case let .script(path):
			var context = [
				"inputString": parsed.arguments.rest,
				"path": path,
			]
			if let targetChannel {
				context["targetChannel"] = targetChannel.name
			}
			executeGlasstualCmdScript(inContext: context)
		case .none:
			sendCommand(parsed.command.uppercased(), withData: parsed.arguments.rest)
		}
	}

	private func dispatchNativeCommand(
		_ group: IRCLocalCommand.NativeGroup,
		parsed: ParsedUserCommand,
		targetChannel: Channel?
	) {
		switch group {
		case .raw:
			dispatchRawCommand(parsed)
		case .request:
			dispatchNativeRequestCommand(parsed)
		case .operatorControl:
			dispatchNativeOperatorCommand(parsed)
		case .session:
			dispatchNativeSessionCommand(parsed)
		case .notification:
			dispatchNativeNotificationAndConnectionCommand(parsed)
		case .capability:
			dispatchNativeCapabilityCommand(parsed)
		case .information:
			dispatchNativeInformationCommand(parsed, targetChannel: targetChannel)
		case .lag:
			dispatchLagCommand(parsed)
		}
	}

	private func dispatchRawCommand(_ parsed: ParsedUserCommand) {
		guard let command = parsed.localCommand else { return }
		let arguments = parsed.arguments.rest

		switch command {
		case .aquote, .araw:
			guard isConnected else { return }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			for client in currentClients() {
				client.sendLine(arguments)
			}

		case .quote, .raw:
			guard isConnected else { return }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			sendLine(arguments)

		case .cap, .caps:
			let capabilities = enabledCapabilitiesStringValue
			printDebugInformation(
				capabilities.isEmpty
					? IRCCommandStrings.noEnabledCapabilities
					: IRCCommandStrings.enabledCapabilities(capabilities)
			)

		case .debug, .echo:
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			if arguments.caseInsensitiveCompare("raw on") == .orderedSame {
				createRawDataLogQuery()
			} else if arguments.caseInsensitiveCompare("raw off") == .orderedSame {
				destroyRawDataLogQuery()
			} else {
				printDebugInformation(arguments)
			}

		default:
			break
		}
	}

	private func dispatchNativeRequestCommand(_ parsed: ParsedUserCommand) {
		guard let command = parsed.localCommand else { return }
		let arguments = parsed.arguments.rest
		switch command {
		case .ison:
			guard isLoggedIn else { return }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			createHiddenCommandResponses()
			/* One nickname per parameter, and split over as many commands as the
			 list needs. `sendIson` opens a request for each of them. */
			sendIson(forNicknames: LineParser.wireTokens(in: arguments), hideResponse: false)

		case .names:
			guard isLoggedIn else { return }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			createHiddenCommandResponses()
			/* `NAMES #one #two` asks about two channels. Sent as one parameter it
			 asked about a channel whose name has a space in it. */
			send("NAMES", arguments: LineParser.wireTokens(in: arguments))

		case .recv:
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			guard let socket else { return }
			ircConnection(socket, didReceiveData: arguments)

		case .setname:
			guard isLoggedIn else { return }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			guard isCapabilityEnabled(.setName) else {
				printDebugInformation(IRCCommandStrings.setNameUnsupported)
				return
			}
			send("SETNAME", arguments: [arguments])

		case .wallops:
			guard isLoggedIn else { return }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			send("WALLOPS", arguments: [arguments])

		default:
			break
		}
	}

	private func dispatchNativeOperatorCommand(_ parsed: ParsedUserCommand) {
		guard let command = parsed.localCommand else { return }
		var arguments = parsed.arguments
		switch command {
		case .gline, .gzline, .shun, .tempshun, .zline:
			guard isLoggedIn else { return }
			let firstSegment = arguments.next()
			let secondSegment = arguments.next()
			/* An absent reason is no parameter at all. Passed through as an empty
			 string it became a bare trailing colon — `GLINE nick 30d :` — which
			 several ircds read as a reason of one space. */
			send(
				parsed.command.uppercased(),
				arguments: [firstSegment, secondSegment, arguments.rest].filter { $0.isEmpty == false }
			)

		case .kill:
			guard isLoggedIn else { return }
			let nickname = arguments.next()
			guard requireArguments(nickname, for: parsed.command) else { return }
			let reason = arguments.isEmpty
				? environment.preferences.irCopDefaultKillMessage
				: arguments.rest
			send("KILL", arguments: [nickname, reason])

		default:
			break
		}
	}

	private func dispatchNativeSessionCommand(_ parsed: ParsedUserCommand) {
		guard let command = parsed.localCommand else { return }
		var arguments = parsed.arguments
		switch command {
		case .conn:
			let serverAddress = arguments.next().lowercased()
			if serverAddress.isEmpty == false {
				guard (serverAddress as NSString).isValidInternetAddress else {
					printDebugInformation(IRCCommandStrings.invalidArguments)
					return
				}
				pendingEndpoint = PendingIRCEndpoint(
					host: serverAddress,
					port: IRCConnectionDefaults.serverPort,
					origin: server,
					reason: .userCommand
				)
			}
			if isConnecting || isConnected {
				addDisconnectCallback { [weak self] in self?.connect() }
				quit()
			} else {
				connect()
			}

		case .back:
			guard isLoggedIn else { return }
			for client in currentClients() where client === self || environment.preferences.awayAllConnections {
				client.toggleAwayStatus(false, withComment: nil)
			}

		case .away:
			guard isLoggedIn else { return }
			broadcastAwayStatus(comment: arguments.rest)

		case .autojoin:
			guard isLoggedIn else { return }
			performAutoJoin(initiatedByUser: true)

		case .nick:
			guard isConnected else { return }
			let nickname = arguments.next()
			guard requireArguments(nickname, for: parsed.command) else { return }
			for client in currentClients() where client === self || environment.preferences.nickAllConnections {
				client.changeNickname(nickname)
			}

		default:
			break
		}
	}

	/** Each connection measures the comment against its own `AWAYLEN`, inside
	 `toggleAwayStatus`, so that the menu item and the screen-sleep timer are
	 bounded the same way this command is. */
	private func broadcastAwayStatus(comment: String) {
		for client in currentClients() where client === self || environment.preferences.awayAllConnections {
			client.toggleAwayStatus(true, withComment: comment)
		}
	}

	private func dispatchNativeNotificationAndConnectionCommand(_ parsed: ParsedUserCommand) {
		guard let command = parsed.localCommand else { return }
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
			guard requireArguments(arguments, for: parsed.command) else { return }
			SharedApplication.sharedNotificationController().scheduleNotification(
				title: ApplicationInfo.applicationName(),
				message: arguments.rest,
				for: notificationChannel,
				on: self
			)

		case .notifysound:
			let sound = arguments.next()
			guard requireArguments(sound, for: parsed.command) else { return }
			SoundPlayer.playAlertSound(sound)

		case .notifyspeak:
			guard requireArguments(arguments, for: parsed.command) else { return }
			SharedApplication.sharedSpeechSynthesizer().speak(text: arguments.rest)

		case .quit:
			guard isConnecting || isConnected else { return }
			if arguments.isEmpty {
				quit()
			} else {
				quit(withComment: arguments.rest)
			}

		case .server:
			guard requireArguments(arguments, for: parsed.command) else { return }
			ServerConnectionCoordinator.connect(
				to: arguments.rest,
				channels: nil,
				options: ServerConnectionOptions(
					connectWhenCreated: true,
					mergeConnectionIfPossible: false,
					selectFirstChannelAdded: false
				)
			)

		case .sslcontext:
			presentCertificateTrustInformation()

		default:
			break
		}
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

	private func dispatchNativeCapabilityCommand(_ parsed: ParsedUserCommand) {
		guard let command = parsed.localCommand else { return }
		let arguments = parsed.arguments.rest
		switch command {
		case .chathistory:
			guard isLoggedIn else { return }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			guard isCapabilityEnabled(.chatHistory) else {
				printDebugInformation(IRCCommandStrings.chatHistoryUnsupported)
				return
			}
			sendLine("CHATHISTORY \(arguments)")

		case .umode:
			guard isLoggedIn else { return }
			/* `/umode +s +cfk` is two mode strings, and each is its own wire
			 parameter; joined into one the server read `+s +cfk` as a single
			 mode string and set nothing after the space. */
			sendModes(arguments, withParametersString: nil, inChannelNamed: userNickname)

		case .monitor, .watch:
			guard isLoggedIn else { return }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			let components = LineParser.wireTokens(in: arguments)
			if components.contains(where: { $0.hasPrefix("-") || $0.hasPrefix("+") }) {
				printDebugInformation(IRCCommandStrings.useAddressBookForTrackedUsers)
				return
			}
			if components.contains(where: { $0.caseInsensitiveCompare("c") == .orderedSame }) == false {
				createHiddenCommandResponses()
			}
			/* One parameter per token, the way the command index describes the
			 command. The raw path this used to take marks no trailing parameter
			 at all, so anything the user typed after a space was left to the
			 server to interpret. */
			send(parsed.command.uppercased(), arguments: components)

		case .silence:
			guard isLoggedIn else { return }
			guard supportInfo.silenceSupported else {
				printDebugInformation(IRCCommandStrings.silenceUnsupported)
				return
			}
			send(parsed.command.uppercased(), arguments: LineParser.wireTokens(in: arguments))

		default:
			break
		}
	}

	private func dispatchNativeInformationCommand(_ parsed: ParsedUserCommand, targetChannel: Channel?) {
		guard let command = parsed.localCommand else { return }
		var arguments = parsed.arguments
		switch command {
		case .who:
			guard isLoggedIn else { return }
			guard requireArguments(arguments, for: parsed.command) else { return }
			createHiddenCommandResponses()
			requestedCommands.recordWhoRequestOpenedAsVisible()
			/* `WHO #chan o` is a target and a flag. Joined into one parameter the
			 server matched a mask with a space in it and answered nothing. */
			send("WHO", arguments: LineParser.wireTokens(in: arguments.rest))

		case .whois:
			guard isLoggedIn else { return }
			var firstNickname = arguments.next()
			if firstNickname.isEmpty, let targetChannel, targetChannel.isPrivateMessage {
				firstNickname = targetChannel.name
			}
			guard requireArguments(firstNickname, for: parsed.command) else { return }
			let secondNickname = arguments.next()
			send("WHOIS", arguments: [firstNickname, secondNickname.isEmpty ? firstNickname : secondNickname])

		case .weights:
			printNicknameWeights(in: targetChannel)

		case .myversion:
			printApplicationVersion(to: targetChannel)

		case .tage:
			let elapsed = Date().timeIntervalSince1970 - ApplicationInfo.applicationBirthday()
			let readableElapsed = humanReadableTimeInterval(elapsed, false, 0)
			let message = IRCCommandStrings.timeSinceFirstCommit(readableElapsed)
			if let targetChannel {
				sendPrivmsg(message, to: targetChannel)
			} else {
				printDebugInformation(toConsole: message)
			}

		default:
			break
		}
	}

	private func printNicknameWeights(in targetChannel: Channel?) {
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

	private func printApplicationVersion(to targetChannel: Channel?) {
		let buildType = IRCCommandStrings.classicBinaryArchitecture(IRCCommandStrings.appleSilicon)
		var message = IRCCommandStrings.version(
			applicationName: ApplicationInfo.applicationName(),
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

	private func dispatchLagCommand(_ parsed: ParsedUserCommand) {
		guard isLoggedIn, let socket else { return }
		var queryItems = [
			URLQueryItem(name: "connection", value: socket.uniqueIdentifier),
			URLQueryItem(name: "time", value: String(Date().timeIntervalSince1970)),
		]
		if parsed.localCommand == .mylag,
		   let channel = output?.selectedChannel(on: self)
		{
			queryItems.append(URLQueryItem(name: "channel", value: channel.name))
		}
		var components = URLComponents()
		components.queryItems = queryItems
		let payload = components.percentEncodedQuery ?? ""
		sendCTCPQuery(userNickname, command: "LAGCHECK", text: payload)
		printDebugInformation(IRCCommandStrings.waitingForLagCheck)
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
	) -> Channel? {
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
