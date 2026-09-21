// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/* The slash commands that write `ServerConfig`: `/ignore`, `/unignore` and
 `/defaults` all edit the connection's stored configuration and broadcast the
 edit, which is why they answer from one file. */

private enum ServerConfigFeature: String {
	case ignoresBouncerUserNotifications = "Ignore Notifications by Private ZNC Users"
	case sendsAuthenticationRequestsToUserServ = "Send Authentication Requests to UserServ"
	case disablesAutomaticSASLExternal = "Disable Automatic SASL EXTERNAL Response"
	case sendsWhoRequestsToChannels = "Send WHO Command Requests to Channels"

	func set(_ enabled: Bool, on config: inout ServerConfig) {
		switch self {
		case .ignoresBouncerUserNotifications: config.zncIgnoreUserNotifications = enabled
		case .sendsAuthenticationRequestsToUserServ: config.sendAuthenticationRequestsToUserServ = enabled
		case .disablesAutomaticSASLExternal: config.saslAuthenticationDisableExternalMechanism = enabled
		case .sendsWhoRequestsToChannels: config.sendWhoCommandRequestsToChannels = enabled
		}
	}
}

/// What a `/defaults` line asks for.
enum DefaultsCommandRequest: Equatable {
	case help
	case change(featureName: String, enabled: Bool, appliesToAllSessions: Bool)

	/** Reads `/defaults help` and `/defaults enable|disable [-a] "Feature"`, or
	 `nil` for anything else.

	 Anything but the two actions used to read as "disable". `-a` is a flag, read
	 bare or quoted — read only as a quoted token it was found only when the user
	 had put it in quotes — and consumed only when it is the flag.
	 A feature name is quoted because it has spaces in it, but an unquoted one
	 is taken whole. */
	init?(_ arguments: CommandArguments) {
		var arguments = arguments
		let enabled: Bool

		switch arguments.next().lowercased() {
		case "help":
			self = .help
			return
		case "enable":
			enabled = true
		case "disable":
			enabled = false
		default:
			return nil
		}

		var lookahead = arguments
		var flag = lookahead.nextQuoted()
		if flag.isEmpty {
			flag = lookahead.next()
		}
		let appliesToAllSessions = flag == "-a"
		if appliesToAllSessions {
			arguments = lookahead
		}

		var featureName = arguments.nextQuoted()
		if featureName.isEmpty {
			featureName = arguments.rest.trimmingCharacters(in: .whitespaces)
		}

		guard featureName.isEmpty == false else {
			return nil
		}

		self = .change(featureName: featureName, enabled: enabled, appliesToAllSessions: appliesToAllSessions)
	}
}

@MainActor
extension ServerSession {
	/// `/defaults` and `/ignore` both edit the connection's stored configuration.
	func dispatchConfigurationCommand(
		_ command: LocalCommand,
		parsed: ParsedUserCommand,
		targetConversation: Conversation?
	) {
		switch command {
		case .defaults:
			dispatchDefaultsCommand(parsed)
		default:
			dispatchIgnoreCommand(command, parsed: parsed, targetConversation: targetConversation)
		}
	}

	private func dispatchDefaultsCommand(_ parsed: ParsedUserCommand) {
		guard let request = DefaultsCommandRequest(parsed.arguments) else {
			printDebugInformation(String(localized: .IRC.invalidSyntaxTypeDefaultsHelp))
			return
		}

		guard case let .change(featureName, enablesFeature, appliesToAll) = request else {
			printDebugInformation(multiline: String(localized: .IRC.defaultsCommandCanBeUsed))
			return
		}

		guard let feature = ServerConfigFeature(rawValue: featureName) else {
			printDebugInformation(
				enablesFeature
					? String(localized: .IRC.cannotEnableTheFeatureBecause(featureName))
					: String(localized: .IRC.cannotDisableTheFeatureBecause(featureName))
			)
			return
		}
		for session in broadcastTargets(whenAllConnections: appliesToAll) {
			var mutableConfig = session.config
			feature.set(enablesFeature, on: &mutableConfig)
			session.updateConfig(mutableConfig)
			session.printDebugInformation(
				enablesFeature
					? String(localized: .IRC.enabledFeature(featureName))
					: String(localized: .IRC.disabledFeature(featureName))
			)
		}
		chatSession?.save()
	}

	private func dispatchIgnoreCommand(
		_ command: LocalCommand,
		parsed: ParsedUserCommand,
		targetConversation: Conversation?
	) {
		let isIgnore = command == .ignore
		var arguments = parsed.arguments
		let nickname = arguments.next()
		guard nickname.isEmpty == false, targetConversation != nil, let member = findUser(nickname) else {
			menu?.showServerPropertiesSheet(
				for: self,
				selection: isIgnore ? .newIgnoreEntry(hostmask: nickname) : .addressBook
			)
			return
		}
		let hostmask = member.hostmask ?? "\(nickname)!*@*"
		let matches = findIgnores(forHostmask: hostmask)
		if isIgnore, matches.isEmpty == false {
			printDebugInformation(String(localized: .IRC.ignoreAlreadyExistsThatMatches(member.nickname)))
			return
		}
		if isIgnore == false, matches.isEmpty {
			printDebugInformation(String(localized: .IRC.noIgnoresCouldBeFound(member.nickname)))
			return
		}
		if isIgnore == false, matches.count > 1 {
			printDebugInformation(String(localized: .IRC.cannotRemoveIgnoreForBecauseGlasstual(member.nickname)))
			return
		}
		var mutableConfig = config
		if isIgnore {
			let ignore = AddressBookEntry.newIgnoreEntry(forHostmask: banMask(for: member))
			printDebugInformation(
				String(localized: .IRC.addedIgnoreThatMatchesWithPattern(member.nickname, ignore.hostmask))
			)
			mutableConfig.ignoreList.append(ignore)
		} else if let ignore = matches.first {
			printDebugInformation(
				String(localized: .IRC.removedIgnoreThatMatchesWithPattern(member.nickname, ignore.hostmask))
			)
			mutableConfig.ignoreList.removeAll { $0.uniqueIdentifier == ignore.uniqueIdentifier }
		}
		updateConfig(mutableConfig)
		clearAddressBookCache(forHostmask: hostmask)
	}
}
