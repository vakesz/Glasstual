// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

private enum ClientDefaultFeature: String {
	case ignoresBouncerUserNotifications = "Ignore Notifications by Private ZNC Users"
	case sendsAuthenticationRequestsToUserServ = "Send Authentication Requests to UserServ"
	case disablesAutomaticSASLExternal = "Disable Automatic SASL EXTERNAL Response"
	case sendsWhoRequestsToChannels = "Send WHO Command Requests to Channels"

	func set(_ enabled: Bool, on config: inout ClientConfig) {
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
	case change(featureName: String, enabled: Bool, appliesToAllClients: Bool)

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
		let appliesToAllClients = flag == "-a"
		if appliesToAllClients {
			arguments = lookahead
		}

		var featureName = arguments.nextQuoted()
		if featureName.isEmpty {
			featureName = arguments.rest.trimmingCharacters(in: .whitespaces)
		}

		guard featureName.isEmpty == false else {
			return nil
		}

		self = .change(featureName: featureName, enabled: enabled, appliesToAllClients: appliesToAllClients)
	}
}

@MainActor
extension Client {
	func dispatchDefaultsCommand(_ parsed: ParsedUserCommand) {
		guard let request = DefaultsCommandRequest(parsed.arguments) else {
			printDebugInformation(String(localized: .IRC.invalidSyntaxTypeDefaultsHelp))
			return
		}

		guard case let .change(featureName, enablesFeature, appliesToAll) = request else {
			printDebugInformation(multiline: String(localized: .IRC.defaultsCommandCanBeUsed))
			return
		}

		guard let feature = ClientDefaultFeature(rawValue: featureName) else {
			printDebugInformation(
				enablesFeature
					? String(localized: .IRC.cannotEnableTheFeatureBecause(featureName))
					: String(localized: .IRC.cannotDisableTheFeatureBecause(featureName))
			)
			return
		}
		for client in (clientDirectory?.clientList ?? []) where client === self || appliesToAll {
			var mutableConfig = client.config
			feature.set(enablesFeature, on: &mutableConfig)
			client.updateConfig(mutableConfig)
			client.printDebugInformation(
				enablesFeature
					? String(localized: .IRC.enabledFeature(featureName))
					: String(localized: .IRC.disabledFeature(featureName))
			)
		}
		clientDirectory?.save()
	}
}
