/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

import Foundation

nonisolated enum IRCCommandStrings {
	static var channelRequired: String {
		String(localized: .IRC.thisCommandCanOnlyBeUsed)
	}

	static var queryRequired: String {
		String(localized: .IRC.thisCommandCanOnlyBeUsedWithAQuery)
	}

	static var invalidArguments: String {
		String(localized: .IRC.oneOrMoreArgumentsAreNot)
	}

	static var nicknameColorsMustBeEnabled: String {
		String(localized: .IRC.thisCommandCannotBeUsedUnless)
	}

	static var noEnabledCapabilities: String {
		String(localized: .IRC.thereAreNoCapabilities)
	}

	static var soundAlreadyMuted: String {
		String(localized: .IRC.soundIsAlreadyMuted)
	}

	static var soundMuted: String {
		String(localized: .IRC.soundHasBeenMuted)
	}

	static var soundNotMuted: String {
		String(localized: .IRC.soundIsNotMuted)
	}

	static var soundUnmuted: String {
		String(localized: .IRC.soundIsNoLongerMuted)
	}

	static var chatHistoryUnsupported: String {
		String(localized: .IRC.thisServerDoesNotSupportChat)
	}

	static var silenceUnsupported: String {
		String(localized: .IRC.thisServerDoesNotAdvertiseSupport)
	}

	static var useAddressBookForTrackedUsers: String {
		String(localized: .IRC.pleaseUseTheAddressBook)
	}

	static var noNicknameWeights: String {
		String(localized: .IRC.noWeights)
	}

	static var appleSilicon: String {
		String(localized: .IRC.appleSilicon)
	}

	static var waitingForLagCheck: String {
		String(localized: .IRC.waitingForResponseFromLagCheck)
	}

	static var setNameUnsupported: String {
		String(localized: .IRC.thisServerDoesNotSupportChanging)
	}

	static var commandUnavailableInWindow: String {
		String(localized: .IRC.thisCommandCannotBeUsedWithin)
	}

	static var developerModeRequired: String {
		String(localized: .IRC.developerModeRequired)
	}

	static func preventedSelfBan(serverAddress: String) -> String {
		String(localized: .IRC.glasstualHasPreventedYouFromBanning(serverAddress))
	}

	static func unsupportedMode(_ mode: String) -> String {
		String(localized: .IRC.modeIsNotSupported(mode))
	}

	static func kickMessageTooLong(networkName: String, maximumLength: Int) -> String {
		String(localized: .IRC.youHaveExceededTheMaximumKick(networkName, maximumLength))
	}

	static func topicTooLong(networkName: String, maximumLength: Int) -> String {
		String(localized: .IRC.youHaveExceededTheMaximumTopic(networkName, maximumLength))
	}

	static func awayMessageTooLong(networkName: String, maximumLength: Int) -> String {
		String(localized: .IRC.youHaveExceededTheMaximumAway(networkName, maximumLength))
	}

	static func channelNotFound(_ channelName: String) -> String {
		String(localized: .IRC.cannotFindChannelNamed(channelName))
	}

	static func invalidNicknameForColor(_ nickname: String) -> String {
		String(localized: .IRC.cannotSetColorForBecause(nickname))
	}

	static func pluginAndScriptConflict(command: String) -> String {
		String(localized: .IRC.commandIsDefinedByAPlugin(command))
	}

	static func enabledCapabilities(_ capabilities: String) -> String {
		String(localized: .IRC.followingCapabilitiesAreCurrentlyEnabled(capabilities))
	}

	static func nicknameWeights(channelName: String) -> String {
		String(localized: .IRC.nicknameCompletionWeights(channelName))
	}

	static func nicknameWeight(
		_ nickname: String,
		sent: Double,
		received: Double,
		total: Double
	) -> String {
		String(localized: .IRC.sentReceiveTotal(nickname, Float(sent), Float(received), Float(total)))
	}

	static func classicBinaryArchitecture(_ architecture: String) -> String {
		String(localized: .IRC.asClassicBinaryOnAnMac(architecture))
	}

	static func version(
		applicationName: String,
		shortVersion: String,
		buildVersion: String,
		buildSuffix: String,
		buildType: String
	) -> String {
		String(localized: .IRC.myversionCommandBuild(
			applicationName,
			shortVersion,
			buildVersion,
			buildSuffix,
			buildType
		))
	}

	static func sharingVersion(_ version: String) -> String {
		String(localized: .IRC.iAmUsing(version))
	}

	static func timeSinceFirstCommit(_ duration: String) -> String {
		String(localized: .IRC.timeSinceFirstCommit(duration))
	}

	static func invalidSyntax(_ syntax: String) -> String {
		String(localized: .IRC.invalidSyntax(syntax))
	}
}

extension IRCCommandStrings {
	nonisolated enum Defaults {
		static var invalidSyntax: String {
			String(localized: .IRC.invalidSyntaxTypeDefaultsHelp)
		}

		static var help: String {
			String(localized: .IRC.defaultsCommandCanBeUsed)
		}

		static func unsupportedFeature(_ featureName: String, enabling: Bool) -> String {
			if enabling {
				return String(localized: .IRC.cannotEnableTheFeatureBecause(featureName))
			}

			return String(localized: .IRC.cannotDisableTheFeatureBecause(featureName))
		}

		static func featureChanged(_ featureName: String, enabled: Bool) -> String {
			if enabled {
				return String(localized: .IRC.enabledFeature(featureName))
			}

			return String(localized: .IRC.disabledFeature(featureName))
		}
	}

	nonisolated enum Ignore {
		static func alreadyExists(nickname: String) -> String {
			String(localized: .IRC.ignoreAlreadyExistsThatMatches(nickname))
		}

		static func notFound(nickname: String) -> String {
			String(localized: .IRC.noIgnoresCouldBeFound(nickname))
		}

		static func ambiguous(nickname: String) -> String {
			String(localized: .IRC.cannotRemoveIgnoreForBecauseGlasstual(nickname))
		}

		static func added(nickname: String, hostmask: String) -> String {
			String(localized: .IRC.addedIgnoreThatMatchesWithPattern(nickname, hostmask))
		}

		static func removed(nickname: String, hostmask: String) -> String {
			String(localized: .IRC.removedIgnoreThatMatchesWithPattern(nickname, hostmask))
		}
	}
}

enum IRCTimerHelpTopic: String {
	case add
	case remove
	case list
	case stop
	case restart
}

nonisolated enum IRCTimerStrings {
	static var invalidSyntax: String {
		String(localized: .IRC.invalidSyntaxTypeTimerHelp)
	}

	static var separator: String {
		String(localized: .IRC.timerCommand)
	}

	static var active: String {
		String(localized: .IRC.timerCommandActive)
	}

	static var stopped: String {
		String(localized: .IRC.timerCommandStopped)
	}

	static var noLimit: String {
		String(localized: .IRC.noLimit)
	}

	static var identifierInvalid: String {
		String(localized: .IRC.timerIdentifierIsNotProperlyFormatted)
	}

	static var allRemoved: String {
		String(localized: .IRC.allTimersRemoved)
	}

	static var none: String {
		String(localized: .IRC.thereAreNoTimers)
	}

	static var invalidInterval: String {
		String(localized: .IRC.timerIntervalMustBeAWhole)
	}

	static var invalidRepeatCount: String {
		String(localized: .IRC.timerRepeatCountMust)
	}

	static func status(active isActive: Bool) -> String {
		isActive ? active : stopped
	}

	static func help(topic: IRCTimerHelpTopic?) -> String {
		switch topic {
		case .add: String(localized: .IRC.timerSecondsRepeatCommandSeconds)
		case .remove: String(localized: .IRC.timerRemoveIdentifierRemoveTheTimer)
		case .list: String(localized: .IRC.timerListListTimers)
		case .stop: String(localized: .IRC.timerStopIdentifierStopTheTimer)
		case .restart: String(localized: .IRC.timerRestartIdentifierRestartTheTimer)
		case nil: String(localized: .IRC.timerCommandCanBeUsed)
		}
	}

	static func alreadyStopped(identifier: String) -> String {
		String(localized: .IRC.timerWithIdentifierIsAlreadyStopped(identifier))
	}

	static func stopped(identifier: String) -> String {
		String(localized: .IRC.timerWithIdentifierStopped(identifier))
	}

	static func restarted(identifier: String) -> String {
		String(localized: .IRC.timerWithIdentifierRestarted(identifier))
	}

	static func cannotRestart(identifier: String) -> String {
		String(localized: .IRC.timerWithIdentifierCantBeRestarted(identifier))
	}

	static func removed(identifier: String) -> String {
		String(localized: .IRC.timerWithIdentifierRemoved(identifier))
	}

	static func notFound(identifier: String) -> String {
		String(localized: .IRC.timerWithIdentifierDoesNotExist(identifier))
	}

	static func count(_ count: Int) -> String {
		String(localized: .IRC.timerCount(count))
	}

	static func summary(
		identifier: String,
		status: String,
		interval: String,
		nextFire: String,
		command: String
	) -> String {
		String(localized: .IRC.idStatusIntervalNextFireCommand(identifier, status, interval, nextFire, command))
	}

	static func repeatingSummary(
		identifier: String,
		status: String,
		interval: String,
		nextFire: String,
		repeatLimit: String,
		iteration: UInt,
		command: String
	) -> String {
		String(
			localized: .IRC.idStatusIntervalNextFireRepeat(
				identifier,
				status,
				interval,
				nextFire,
				repeatLimit,
				Int(iteration),
				command
			)
		)
	}
}
