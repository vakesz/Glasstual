// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// When this project's first commit landed, as a Unix timestamp. `/tage` is
/// the only thing that asks, and it asks for the interval since.
private let firstCommitTimestamp: TimeInterval = 1_279_871_580

@MainActor
extension ServerSession {
	func dispatchRawCommand(_ command: LocalCommand, parsed: ParsedUserCommand) {
		let arguments = parsed.arguments.rest

		switch command {
		case .aquote, .araw:
			guard isConnected else { return }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			for session in allSessions {
				session.sendLine(arguments)
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
				createRawDataLogConsole()
			} else if arguments.caseInsensitiveCompare("raw off") == .orderedSame {
				destroyRawDataLogConsole()
			} else {
				printDebugInformation(arguments)
			}

		default:
			break
		}
	}

	func dispatchNativeRequestCommand(_ command: LocalCommand, parsed: ParsedUserCommand) {
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
			send(.names, arguments: LineParser.wireTokens(in: arguments))

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
			send(.setname, arguments: [arguments])

		case .wallops:
			guard isLoggedIn else { return }
			guard requireArguments(parsed.arguments, for: parsed.command) else { return }
			send(.wallops, arguments: [arguments])

		default:
			break
		}
	}

	func dispatchNativeOperatorCommand(_ command: LocalCommand, parsed: ParsedUserCommand) {
		var arguments = parsed.arguments
		switch command {
		case .gline, .gzline, .shun, .tempshun, .zline:
			guard isLoggedIn, let wireCommand = command.relayedRemoteCommand else { return }
			let firstSegment = arguments.next()
			let secondSegment = arguments.next()
			/* An absent reason is no parameter at all. Passed through as an empty
			 string it became a bare trailing colon — `GLINE nick 30d :` — which
			 several ircds read as a reason of one space. */
			send(
				wireCommand,
				arguments: [firstSegment, secondSegment, arguments.rest].filter { $0.isEmpty == false }
			)

		case .kill:
			guard isLoggedIn else { return }
			let nickname = arguments.next()
			guard requireArguments(nickname, for: parsed.command) else { return }
			let reason = arguments.isEmpty
				? environment.settings.irCopDefaultKillMessage
				: arguments.rest
			send(.kill, arguments: [nickname, reason])

		default:
			break
		}
	}

	func dispatchSessionCommand(_ command: LocalCommand, parsed: ParsedUserCommand) {
		var arguments = parsed.arguments
		switch command {
		case .conn:
			reconnect(toServerAddress: arguments.next().lowercased())

		case .back:
			guard isLoggedIn else { return }
			for session in broadcastTargets(whenAllConnections: environment.settings.awayAllConnections) {
				session.toggleAwayStatus(false, withComment: nil)
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
			for session in broadcastTargets(whenAllConnections: environment.settings.nickAllConnections) {
				session.changeNickname(nickname)
			}

		case .quit:
			guard isConnecting || isConnected else { return }
			if arguments.isEmpty {
				quit()
			} else {
				quit(withComment: arguments.rest)
			}

		case .server:
			guard requireArguments(arguments, for: parsed.command) else { return }
			ServerConnection.connect(
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

	/** `/conn [server]`: reconnects, moving to the endpoint the user named
	 first where they named one. A connection already up is quit and reconnected
	 from the disconnect callback, so the new endpoint is the one it comes back
	 on. */
	private func reconnect(toServerAddress serverAddress: String) {
		if serverAddress.isEmpty == false {
			guard serverAddress.isValidInternetAddress else {
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
	}

	/** Each connection measures the comment against its own `AWAYLEN`, inside
	 `toggleAwayStatus`, so that the menu item and the screen-sleep timer are
	 bounded the same way this command is. */
	private func broadcastAwayStatus(comment: String) {
		for session in broadcastTargets(whenAllConnections: environment.settings.awayAllConnections) {
			session.toggleAwayStatus(true, withComment: comment)
		}
	}

	func dispatchNotificationCommand(_ command: LocalCommand, parsed: ParsedUserCommand) {
		var arguments = parsed.arguments
		switch command {
		case .mute:
			toggleNotificationSoundMute(true)

		case .unmute:
			toggleNotificationSoundMute(false)

		case .notifybubble:
			let notificationChannel = stringIsChannelName(arguments.rest)
				? findConversation(arguments.next())
				: nil
			guard requireArguments(arguments, for: parsed.command) else { return }
			environment.services.notifications?.post(PendingUserNotification(
				event: .addressBookMatch,
				title: ApplicationInfo.applicationName(),
				subtitle: nil,
				body: arguments.rest,
				payload: UserNotificationPayload(
					sessionIdentifier: uniqueIdentifier,
					conversationIdentifier: notificationChannel?.uniqueIdentifier
				),
				playsSound: false
			))

		case .notifysound:
			let sound = arguments.next()
			guard requireArguments(sound, for: parsed.command) else { return }
			environment.services.notifications?.playAlertSound(named: sound)

		default:
			break
		}
	}

	private func toggleNotificationSoundMute(_ muted: Bool) {
		let alreadyInState = environment.settings.soundIsMuted == muted
		guard alreadyInState == false else {
			printDebugInformation(muted ? String(localized: .IRC.soundIsAlreadyMuted) : String(localized: .IRC.soundIsNotMuted))
			return
		}
		printDebugInformation(muted ? String(localized: .IRC.soundHasBeenMuted) : String(localized: .IRC.soundIsNoLongerMuted))
		menu?.toggleMuteOnNotificationSoundsShortcut(on: muted)
	}

	func dispatchNativeCapabilityCommand(_ command: LocalCommand, parsed: ParsedUserCommand) {
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
			guard isLoggedIn, let wireCommand = command.relayedRemoteCommand else { return }
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
			send(wireCommand, arguments: components)

		case .silence:
			guard isLoggedIn else { return }
			guard supportInfo.silenceSupported else {
				printDebugInformation(String(localized: .IRC.thisServerDoesNotAdvertiseSupport))
				return
			}
			send(.silence, arguments: LineParser.wireTokens(in: arguments))

		default:
			break
		}
	}

	func dispatchNativeInformationCommand(
		_ command: LocalCommand,
		parsed: ParsedUserCommand,
		targetConversation: Conversation?
	) {
		var arguments = parsed.arguments
		switch command {
		case .who:
			guard isLoggedIn else { return }
			guard requireArguments(arguments, for: parsed.command) else { return }
			createHiddenCommandResponses()
			requestedCommands.recordWhoRequestOpenedAsVisible()
			/* `WHO #chan o` is a target and a flag. Joined into one parameter the
			 server matched a mask with a space in it and answered nothing. */
			send(.who, arguments: LineParser.wireTokens(in: arguments.rest))

		case .whois:
			guard isLoggedIn else { return }
			var firstNickname = arguments.next()
			if firstNickname.isEmpty, let targetConversation, targetConversation.isDirect {
				firstNickname = targetConversation.name
			}
			guard requireArguments(firstNickname, for: parsed.command) else { return }
			let secondNickname = arguments.next()
			send(.whois, arguments: [firstNickname, secondNickname.isEmpty ? firstNickname : secondNickname])

		case .weights:
			printNicknameWeights(in: targetConversation)

		case .myversion:
			printApplicationVersion(to: targetConversation)

		case .lagcheck, .mylag:
			printLagCheck(command)

		case .tage:
			let elapsed = Date().timeIntervalSince1970 - firstCommitTimestamp
			let readableElapsed = DateFormatting.humanReadable(elapsed, shortValue: false)
			let message = String(localized: .IRC.timeSinceFirstCommit(readableElapsed))
			if let targetConversation {
				sendPrivmsg(message, to: targetConversation)
			} else {
				printDebugInformation(toConsole: message)
			}

		default:
			break
		}
	}

	/// `/lagcheck` times the round trip; `/mylag` also reports it into the
	/// conversation the user is looking at.
	private func printLagCheck(_ command: LocalCommand) {
		guard isLoggedIn, let socket else { return }
		var fields = [
			(key: "connection", value: socket.uniqueIdentifier),
			(key: "time", value: String(Date().timeIntervalSince1970)),
		]
		if command == .mylag,
		   let conversation = output?.selectedConversation(on: self)
		{
			// "channel" is the field name the lag-check CTCP payload carries.
			fields.append((key: "channel", value: conversation.name))
		}
		let payload = CTCPPolicy.formEncoded(fields)
		sendCTCPQuery(userNickname, command: .lagCheck, text: payload)
		printDebugInformation(String(localized: .IRC.waitingForResponseFromLagCheck))
	}

	// MARK: - Reports

	func printNicknameWeights(in targetConversation: Conversation?) {
		guard let targetConversation, targetConversation.isChannel else {
			printDebugInformation(String(localized: .IRC.thisCommandCanOnlyBeUsed))
			return
		}
		printDebugInformation(String(localized: .IRC.nicknameCompletionWeights(targetConversation.name)))
		var hasWeights = false
		for member in targetConversation.memberList {
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

	func printApplicationVersion(to targetConversation: Conversation?) {
		let buildType = String(localized: .IRC.asClassicBinaryOnAnMac(String(localized: .IRC.appleSilicon)))
		var message = String(localized: .IRC.myversionCommandBuild(
			ApplicationInfo.applicationName(),
			ApplicationInfo.applicationVersionShort(),
			ApplicationInfo.applicationVersion(),
			"",
			buildType
		))
		if let targetConversation {
			message = String(localized: .IRC.iAmUsing(message))
			sendPrivmsg(message, to: targetConversation)
		} else {
			printDebugInformation(toConsole: message)
		}
	}
}
