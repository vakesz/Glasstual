// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

@MainActor
extension Client {
	func sendCommand(_ input: Any, completeTarget: Bool = true, target targetChannelName: String? = nil) {
		guard let parsed = ParsedUserCommand(input) else { return }
		guard allowsDeveloperModeCommand(parsed) else { return }

		let targetChannel = resolvedTargetChannel(
			completeTarget: completeTarget,
			targetChannelName: targetChannelName
		)

		/* A name the client has no handler for is not an error: it belongs to a
		 user script or to the server. */
		guard let group = parsed.localCommand?.group else {
			dispatchScriptOrRawCommand(parsed, targetChannel: targetChannel)

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
		printDebugInformation(String(localized: .IRC.developerModeRequired))
		return false
	}

	private func dispatchScriptOrRawCommand(_ parsed: ParsedUserCommand, targetChannel: Channel?) {
		guard let path = AppServices.scripts.scriptPath(forOutgoingCommand: parsed.command) else {
			sendCommand(parsed.command.uppercased(), withData: parsed.arguments.rest)
			return
		}

		var context = [
			"inputString": parsed.arguments.rest,
			"path": path,
		]
		if let targetChannel {
			context["targetChannel"] = targetChannel.name
		}
		executeGlasstualCmdScript(inContext: context)
	}

	private func dispatchNativeCommand(
		_ group: LocalCommand.NativeGroup,
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
		case .bouncer:
			dispatchBouncerCommand(parsed, targetChannel: targetChannel)
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
					? String(localized: .IRC.thereAreNoCapabilities)
					: String(localized: .IRC.followingCapabilitiesAreCurrentlyEnabled(capabilities))
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
			guard socket != nil else { return }
			connectionDidReceive(arguments)

		case .setname:
			guard isLoggedIn else { return }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			guard isCapabilityEnabled(.setName) else {
				printDebugInformation(String(localized: .IRC.thisServerDoesNotSupportChanging))
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
					printDebugInformation(String(localized: .IRC.oneOrMoreArgumentsAreNot))
					return
				}
				pendingEndpoint = connectCommandEndpoint(host: serverAddress)
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
			AppServices.notifications.scheduleNotification(
				title: ApplicationInfo.applicationName(),
				message: arguments.rest,
				for: notificationChannel,
				on: self
			)

		case .notifysound:
			let sound = arguments.next()
			guard requireArguments(sound, for: parsed.command) else { return }
			SoundPlayer.playAlertSound(sound)

		case .quit:
			guard isConnecting || isConnected else { return }
			if arguments.isEmpty {
				quit()
			} else {
				quit(withComment: arguments.rest)
			}

		case .server:
			guard requireArguments(arguments, for: parsed.command) else { return }
			ServerConnectionController.connect(
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
			printDebugInformation(muted ? String(localized: .IRC.soundIsAlreadyMuted) : String(localized: .IRC.soundIsNotMuted))
			return
		}
		printDebugInformation(muted ? String(localized: .IRC.soundHasBeenMuted) : String(localized: .IRC.soundIsNoLongerMuted))
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
				printDebugInformation(String(localized: .IRC.thisServerDoesNotSupportChat))
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
				printDebugInformation(String(localized: .IRC.pleaseUseTheAddressBook))
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
				printDebugInformation(String(localized: .IRC.thisServerDoesNotAdvertiseSupport))
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
			let readableElapsed = DateFormatting.humanReadable(elapsed, shortValue: false)
			let message = String(localized: .IRC.timeSinceFirstCommit(readableElapsed))
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
			printDebugInformation(String(localized: .IRC.thisCommandCanOnlyBeUsed))
			return
		}
		printDebugInformation(String(localized: .IRC.nicknameCompletionWeights(targetChannel.name)))
		var hasWeights = false
		for member in targetChannel.memberList {
			let incomingWeight = member.incomingWeight
			let outgoingWeight = member.outgoingWeight
			let combinedWeight = incomingWeight + outgoingWeight
			guard combinedWeight > 0 else { continue }
			hasWeights = true
			printDebugInformation(
				String(localized: .IRC.sentReceiveTotal(
					member.user.nickname,
					Float(outgoingWeight),
					Float(incomingWeight),
					Float(combinedWeight)
				))
			)
		}
		if hasWeights == false {
			printDebugInformation(String(localized: .IRC.noWeights))
		}
	}

	private func printApplicationVersion(to targetChannel: Channel?) {
		let buildType = String(localized: .IRC.asClassicBinaryOnAnMac(String(localized: .IRC.appleSilicon)))
		var message = String(localized: .IRC.myversionCommandBuild(
			ApplicationInfo.applicationName(),
			ApplicationInfo.applicationVersionShort(),
			ApplicationInfo.applicationVersion(),
			"",
			buildType
		))
		if let targetChannel {
			message = String(localized: .IRC.iAmUsing(message))
			sendPrivmsg(message, to: targetChannel)
		} else {
			printDebugInformation(toConsole: message)
		}
	}

	private func dispatchLagCommand(_ parsed: ParsedUserCommand) {
		guard isLoggedIn, let socket else { return }
		var fields = [
			(key: "connection", value: socket.uniqueIdentifier),
			(key: "time", value: String(Date().timeIntervalSince1970)),
		]
		if parsed.localCommand == .mylag,
		   let channel = output?.selectedChannel(on: self)
		{
			fields.append((key: "channel", value: channel.name))
		}
		let payload = CTCPPolicy.formEncoded(fields)
		sendCTCPQuery(userNickname, command: "LAGCHECK", text: payload)
		printDebugInformation(String(localized: .IRC.waitingForResponseFromLagCheck))
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

	private func currentClients() -> [Client] {
		(clientDirectory?.clientList ?? [])
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

extension Client {
	/** Writes `command` and `data` to the wire exactly as given.

	 Nothing here marks a trailing parameter, and nothing should: this is the
	 raw path — the one an unrecognised `/command` takes — where the text is the
	 user's and the line is whatever they typed. A parameter of theirs that has
	 to hold spaces needs the colon they typed in front of it, the way it would
	 on any other client's raw line.

	 A command the client itself assembles has parameters it already knows the
	 boundaries of, so it goes through `send(_:arguments:)` instead, which marks
	 the trailing one from `RemoteCommand.trailingParameter`. */
	func sendCommand(_ command: String, withData data: String) {
		sendLine("\(command) \(data)")
	}

	func printInvalidSyntaxMessage(for command: String) {
		guard let localCommand = LocalCommand(typedName: command) else { return }
		printDebugInformation(String(localized: .IRC.invalidSyntax(localCommand.syntax)))
	}
}
