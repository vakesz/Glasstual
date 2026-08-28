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

	func set(_ enabled: Bool, on config: IRCClientConfigMutable) {
		switch self {
		case .ignoresBouncerUserNotifications: config.zncIgnoreUserNotifications = enabled
		case .sendsAuthenticationRequestsToUserServ: config.sendAuthenticationRequestsToUserServ = enabled
		case .disablesAutomaticSASLExternal: config.saslAuthenticationDisableExternalMechanism = enabled
		case .sendsWhoRequestsToChannels: config.sendWhoCommandRequestsToChannels = enabled
		}
	}
}

@MainActor
extension IRCClient {
	func dispatchDefaultsCommand(_ parsed: ParsedUserCommand) -> Bool {
		guard parsed.command.caseInsensitiveCompare("defaults") == .orderedSame else { return false }
		let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
		guard arguments.length > 0 else {
			printDebugInformation(IRCCommandStrings.Defaults.invalidSyntax)
			return true
		}
		let action = arguments.nextTokenAsString().lowercased()
		if action == "help" {
			printDebugInformation(multiline: IRCCommandStrings.Defaults.help)
			return true
		}
		var featureName = arguments.nextQuotedTokenAsString()
		let appliesToAll = featureName == "-a"
		if appliesToAll {
			featureName = arguments.nextQuotedTokenAsString()
		}
		guard featureName.isEmpty == false else {
			printDebugInformation(IRCCommandStrings.Defaults.invalidSyntax)
			return true
		}
		let enablesFeature = action == "enable"
		guard let feature = ClientDefaultFeature(rawValue: featureName) else {
			printDebugInformation(
				IRCCommandStrings.Defaults.unsupportedFeature(featureName, enabling: enablesFeature)
			)
			return true
		}
		for client in AppController.shared.world.clientList where client === self || appliesToAll {
			guard let mutableConfig = client.config.mutableCopy() as? IRCClientConfigMutable else { continue }
			feature.set(enablesFeature, on: mutableConfig)
			client.updateConfig(mutableConfig)
			client.printDebugInformation(
				IRCCommandStrings.Defaults.featureChanged(featureName, enabled: enablesFeature)
			)
		}
		AppController.shared.world.save()
		return true
	}
}
