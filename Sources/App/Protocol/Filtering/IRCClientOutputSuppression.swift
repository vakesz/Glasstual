/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
import GlasstualPluginKit

enum IRCOutputDestination {
	case console
	case channel
	case privateMessage
	case other
}

struct IRCOutputSuppressionRule {
	let pattern: String
	let suppressesConsole: Bool
	let suppressesChannel: Bool
	let suppressesPrivateMessage: Bool

	init(pattern: String, console: Bool = false, channel: Bool = false, privateMessage: Bool = false) {
		self.pattern = pattern
		suppressesConsole = console
		suppressesChannel = channel
		suppressesPrivateMessage = privateMessage
	}

	func applies(to destination: IRCOutputDestination) -> Bool {
		switch destination {
		case .console:
			suppressesConsole
		case .channel:
			suppressesChannel
		case .privateMessage:
			suppressesPrivateMessage
		case .other:
			false
		}
	}
}

enum IRCOutputSuppressionPolicy {
	static func matches(
		message: String,
		destination: IRCOutputDestination,
		rules: [IRCOutputSuppressionRule]
	) -> Bool {
		rules.contains { rule in
			/* The destination check is free; the regex is not. */
			rule.applies(to: destination) && RegularExpression.string(message, isMatchedByRegex: rule.pattern)
		}
	}
}

public extension IRCClient {
	func outputRuleMatched(in message: String, channel: IRCChannel?) -> Bool {
		let comparableMessage: String = if environment.preferences.removeAllFormatting {
			message
		} else {
			(message as NSString).stripIRCEffects
		}

		let destination: IRCOutputDestination = if let channel {
			if channel.isChannel {
				.channel
			} else if channel.isPrivateMessage {
				.privateMessage
			} else {
				.other
			}
		} else {
			.console
		}

		let rules = SharedApplication.sharedPluginManager().pluginOutputSuppressionRules.map { rule in
			IRCOutputSuppressionRule(
				pattern: rule.match,
				console: rule.restrictConsole,
				channel: rule.restrictChannel,
				privateMessage: rule.restrictPrivateMessage
			)
		}
		return IRCOutputSuppressionPolicy.matches(
			message: comparableMessage,
			destination: destination,
			rules: rules
		)
	}
}
