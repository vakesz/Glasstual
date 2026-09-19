// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The questions the rest of the session asks the ISUPPORT table.

 Every answer here is a pure function of what a 005 line already stored, so
 nothing in this file writes to the table, to the wire or to the capability
 state — ``ISupport`` itself holds the reading and clearing of tokens. */
extension ISupport {
	func channelLimit(forChannelNamed channel: String) -> UInt {
		guard let prefix = channel.first else {
			return 0
		}

		return channelLimits[prefix] ?? 0
	}

	/** How many targets the server said `command` takes on one line.

	 Zero means the server said nothing usable: it named no `TARGMAX` entry for
	 the command, or named one with an empty limit, and sent no `MAXTARGETS`
	 either. The empty `TARGMAX` limit does mean "no limit" in the specification,
	 but it arrives as the same zero as silence and is read the same
	 conservative way, because the two are worth the same to a session: see
	 ``groupsMultipleTargets(forCommand:)`` for what the session then does.
	 */
	func maximumTargets(forCommand command: String) -> UInt {
		if let limit = maximumTargetsByCommand[command.uppercased()] {
			return limit
		}

		return maximumTargets
	}

	/** Whether several targets may ride on one `command`.

	 Only an advertised limit above one earns a comma-separated target list. A
	 server that advertised nothing (zero) gets one target per line, the same as
	 one that said `TARGMAX=PRIVMSG:1`: a server that does not take a list
	 answers `ERR_TOOMANYTARGETS` or silently drops every target after the
	 first, and the user has no way to tell that the message never arrived. One
	 line per target always arrives, and costs only lines.

	 `JOIN` does not come through here. A comma-separated channel list is core
	 `JOIN` syntax rather than an extension, so ``JoinBatching`` fills a line
	 whether or not the server advertised a `TARGMAX` for it.
	 */
	func groupsMultipleTargets(forCommand command: String) -> Bool {
		maximumTargets(forCommand: command) > 1
	}

	func maximumListEntries(forModeSymbol modeSymbol: ChannelModeSymbol) -> UInt {
		maximumListEntries[modeSymbol.character] ?? 0
	}

	func extendedListSupportsToken(_ token: String) -> Bool {
		extendedListTokens.contains(token.uppercased())
	}

	/** Whether `CLIENTTAGDENY` refuses this client tag.

	 Entries are read in order: `*` denies everything advertised after it and a
	 `-name` entry takes one tag back out of a blanket denial. */
	func isClientTagDenied(_ tagName: String) -> Bool {
		var denied = false

		for entry in clientTagDenyList {
			if entry == "*" {
				denied = true
			} else if entry.hasPrefix("-") {
				if entry.dropFirst().caseInsensitiveCompare(tagName) == .orderedSame {
					return false
				}
			} else if entry.caseInsensitiveCompare(tagName) == .orderedSame {
				denied = true
			}
		}

		return denied
	}

	func descriptionForExtendedBanMask(_ mask: String) -> String? {
		if extendedBanTypes.isEmpty {
			return nil
		}

		var body = mask

		if let prefix = extendedBanPrefix {
			if mask.hasPrefix(prefix) == false {
				return nil
			}

			body = String(mask.dropFirst(prefix.count))
		}

		var negated = false

		if extendedBanPrefix != "~", body.hasPrefix("~"), body.count > 1 {
			negated = true
			body = String(body.dropFirst())
		}

		if body.isEmpty {
			return nil
		}

		let type = String(body.prefix(1))

		if extendedBanTypes.contains(type) == false {
			return nil
		}

		var argument: String?

		if body.count > 2, body[body.index(body.startIndex, offsetBy: 1)] == ":" {
			argument = String(body.dropFirst(2))
		} else if body.count > 1 || extendedBanPrefix == nil {
			return nil
		}

		let description = ExtendedBanKind.describing(type: type, argument: argument)

		if negated {
			return String(localized: .IRC.everyoneExcept(description))
		}

		return description
	}

	func stringValue(forConfiguration configuration: [String: ISupportValue]) -> String? {
		if configuration.isEmpty {
			return nil
		}

		var stringValue = ""

		for key in configuration.keys.sorted() {
			switch configuration[key] {
			case let .text(value):
				stringValue.append("\u{02}\(key)\u{02}=\(value) ")
			case .flag, nil:
				stringValue.append("\u{02}\(key) \u{02}")
			}
		}

		return stringValue
	}

	func casefoldString(_ string: String) -> String {
		userPrefixes.casefold(string)
	}

	/// Whether a mode letter carries a parameter.
	///
	/// Through the same RFC 1459 fallback ``ModeParser/parse(_:channelModeKinds:)``
	/// applies, so that a `MODE` arriving before 005 is answered the same way
	/// whether it is being parsed or being asked about: without it `+b` read as a
	/// bare flag here and as a list mode there.
	func modeHasParameter(_ modeSymbol: String, whenModeIsSet: Bool) -> Bool {
		guard let symbol = modeSymbol.first, modeSymbol.count == 1 else {
			return false
		}

		let modeKinds = ModeParser.effectiveChannelModeKinds(channelModeKinds)
		let policy = modeKinds[symbol]?.parameterPolicy ?? .never

		return policy.requiresParameter(whenModeIsSet: whenModeIsSet)
	}

	func userPrefix(forModeSymbol modeSymbol: String) -> String? {
		userPrefixes.userPrefix(forModeSymbol: modeSymbol)
	}

	func modeSymbolIsUserPrefix(_ modeSymbol: String) -> Bool {
		userPrefix(forModeSymbol: modeSymbol) != nil
	}

	func modeSymbol(forUserPrefix character: String) -> String? {
		userModePrefixPairs.first { $0.character == character }?.modeSymbol
	}

	func characterIsUserPrefix(_ character: String) -> Bool {
		modeSymbol(forUserPrefix: character) != nil
	}

	func rankForUserPrefix(withMode modeSymbol: String) -> UInt {
		userPrefixes.rank(forModeSymbol: modeSymbol)
	}

	func isListSupported(_ listKind: ISupportListKind) -> Bool {
		modeSymbol(forList: listKind) != nil
	}

	func modeSymbol(forList listKind: ISupportListKind) -> String? {
		switch listKind {
		case .ban:
			return "b"
		case .banException:
			return banExceptionModeSymbol
		case .inviteException:
			return inviteExceptionModeSymbol
		case .quiet:
			if modeSymbolIsUserPrefix("q") {
				return nil
			}

			return "q"
		}
	}

	func statusMessagePrefix(forModeSymbol modeSymbol: String) -> String? {
		guard let character = userPrefix(forModeSymbol: modeSymbol) else {
			return nil
		}

		if statusMessagePrefixCharacters.contains(character) == false {
			return nil
		}

		return character
	}

	/// The `STATUSMSG` prefix a target name carries, if the character after it
	/// really does begin a channel name. The target may equally be a nickname,
	/// which never carries one.
	func extractStatusMessagePrefix(fromTargetNamed target: String) -> String {
		if target.count < 2 {
			return ""
		}

		for character in statusMessagePrefixCharacters where target.hasPrefix(character) {
			let nextCharacter = String(target.dropFirst().prefix(1))

			if channelNamePrefixes.contains(nextCharacter) {
				return character
			}
		}

		return ""
	}
}
