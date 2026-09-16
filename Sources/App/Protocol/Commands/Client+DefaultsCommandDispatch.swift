/* *********************************************************************
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
 *********************************************************************** */

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
			printDebugInformation(CommandStrings.Defaults.invalidSyntax)
			return
		}

		guard case let .change(featureName, enablesFeature, appliesToAll) = request else {
			printDebugInformation(multiline: CommandStrings.Defaults.help)
			return
		}

		guard let feature = ClientDefaultFeature(rawValue: featureName) else {
			printDebugInformation(
				CommandStrings.Defaults.unsupportedFeature(featureName, enabling: enablesFeature)
			)
			return
		}
		for client in (world?.clientList ?? []) where client === self || appliesToAll {
			var mutableConfig = client.config
			feature.set(enablesFeature, on: &mutableConfig)
			client.updateConfig(mutableConfig)
			client.printDebugInformation(
				CommandStrings.Defaults.featureChanged(featureName, enabled: enablesFeature)
			)
		}
		world?.save()
	}
}
