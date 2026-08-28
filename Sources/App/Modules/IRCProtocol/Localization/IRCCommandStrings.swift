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

enum IRCCommandStrings {
	static var channelRequired: String {
		String(localized: .IRC.g01Qn)
	}

	static var queryRequired: String {
		String(localized: .IRC.m6OZ1)
	}

	static var invalidArguments: String {
		String(localized: .IRC.zefQ9)
	}

	static var nicknameColorsMustBeEnabled: String {
		String(localized: .IRC._026Qv)
	}

	static var noEnabledCapabilities: String {
		String(localized: .IRC._5WaLb)
	}

	static var soundAlreadyMuted: String {
		String(localized: .IRC.sdnYr)
	}

	static var soundMuted: String {
		String(localized: .IRC.u48Aa)
	}

	static var soundNotMuted: String {
		String(localized: .IRC._5RfMj)
	}

	static var soundUnmuted: String {
		String(localized: .IRC._190F2)
	}

	static var chatHistoryUnsupported: String {
		String(localized: .IRC.hc1Ah)
	}

	static var silenceUnsupported: String {
		String(localized: .IRC.m2VSd)
	}

	static var useAddressBookForTrackedUsers: String {
		String(localized: .IRC.khw4Y)
	}

	static var noNicknameWeights: String {
		String(localized: .IRC.dje41)
	}

	static var appleSilicon: String {
		String(localized: .IRC.g1UOs)
	}

	static var waitingForLagCheck: String {
		String(localized: .IRC.qohKt)
	}

	static var setNameUnsupported: String {
		String(localized: .IRC.setNm)
	}

	static var commandUnavailableInWindow: String {
		String(localized: .IRC.sxfQx)
	}

	static var developerModeRequired: String {
		String(localized: .IRC.developerModeRequired)
	}

	static func preventedSelfBan(serverAddress: String) -> String {
		String(localized: .IRC._0R15L(serverAddress))
	}

	static func unsupportedMode(_ mode: String) -> String {
		String(localized: .IRC.dwiD1(mode))
	}

	static func kickMessageTooLong(networkName: String, maximumLength: Int) -> String {
		String(localized: .IRC._59AIr(networkName, maximumLength))
	}

	static func topicTooLong(networkName: String, maximumLength: Int) -> String {
		String(localized: .IRC._1Oo3B(networkName, maximumLength))
	}

	static func awayMessageTooLong(networkName: String, maximumLength: Int) -> String {
		String(localized: .IRC._41YP2(networkName, maximumLength))
	}

	static func channelNotFound(_ channelName: String) -> String {
		String(localized: .IRC.pxaOx(channelName))
	}

	static func invalidNicknameForColor(_ nickname: String) -> String {
		String(localized: .IRC._8Dy6F(nickname))
	}

	static func pluginAndScriptConflict(command: String) -> String {
		String(localized: .IRC.d3C9B(command))
	}

	static func enabledCapabilities(_ capabilities: String) -> String {
		String(localized: .IRC._7P9Rs(capabilities))
	}

	static func nicknameWeights(channelName: String) -> String {
		String(localized: .IRC.zudU3(channelName))
	}

	static func nicknameWeight(
		_ nickname: String,
		sent: Double,
		received: Double,
		total: Double
	) -> String {
		String(localized: .IRC._24R8C(nickname, Float(sent), Float(received), Float(total)))
	}

	static func classicBinaryArchitecture(_ architecture: String) -> String {
		String(localized: .IRC.b8P44(architecture))
	}

	static func version(
		applicationName: String,
		shortVersion: String,
		buildVersion: String,
		buildSuffix: String,
		buildType: String
	) -> String {
		String(localized: .IRC.ccbUr(applicationName, shortVersion, buildVersion, buildSuffix, buildType))
	}

	static func sharingVersion(_ version: String) -> String {
		String(localized: .IRC.pqj1Y(version))
	}

	static func timeSinceFirstCommit(_ duration: String) -> String {
		String(localized: .IRC.v9X18(duration))
	}

	static func invalidSyntax(_ syntax: String) -> String {
		String(localized: .IRC.atq93(syntax))
	}
}

extension IRCCommandStrings {
	enum Defaults {
		static var invalidSyntax: String {
			String(localized: .IRC._1DzJb)
		}

		static var help: String {
			String(localized: .IRC.bkkLo)
		}

		static func unsupportedFeature(_ featureName: String, enabling: Bool) -> String {
			if enabling {
				return String(localized: .IRC.pc467(featureName))
			}

			return String(localized: .IRC.d7YPv(featureName))
		}

		static func featureChanged(_ featureName: String, enabled: Bool) -> String {
			if enabled {
				return String(localized: .IRC._5Ke18(featureName))
			}

			return String(localized: .IRC._0GnCb(featureName))
		}
	}

	enum Ignore {
		static func alreadyExists(nickname: String) -> String {
			String(localized: .IRC._5IxZn(nickname))
		}

		static func notFound(nickname: String) -> String {
			String(localized: .IRC.wu0Jp(nickname))
		}

		static func ambiguous(nickname: String) -> String {
			String(localized: .IRC.vrx1F(nickname))
		}

		static func added(nickname: String, hostmask: String) -> String {
			String(localized: .IRC.ret20(nickname, hostmask))
		}

		static func removed(nickname: String, hostmask: String) -> String {
			String(localized: .IRC.jzgG8(nickname, hostmask))
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

enum IRCTimerStrings {
	static var invalidSyntax: String {
		String(localized: .IRC.jj994)
	}

	static var separator: String {
		String(localized: .IRC.aoxZz)
	}

	static var active: String {
		String(localized: .IRC.bhz9E)
	}

	static var stopped: String {
		String(localized: .IRC.ww4Sn)
	}

	static var noLimit: String {
		String(localized: .IRC.o26Ae)
	}

	static var identifierInvalid: String {
		String(localized: .IRC.p6LO4)
	}

	static var allRemoved: String {
		String(localized: .IRC._808Bs)
	}

	static var none: String {
		String(localized: .IRC.pqk5K)
	}

	static var invalidInterval: String {
		String(localized: .IRC._327Pv)
	}

	static var invalidRepeatCount: String {
		String(localized: .IRC.eudKc)
	}

	static func status(active isActive: Bool) -> String {
		isActive ? active : stopped
	}

	static func help(topic: IRCTimerHelpTopic?) -> String {
		switch topic {
		case .add: String(localized: .IRC._6R0Il)
		case .remove: String(localized: .IRC.i2DX5)
		case .list: String(localized: .IRC.x1NVe)
		case .stop: String(localized: .IRC.bx2N1)
		case .restart: String(localized: .IRC.r27Tv)
		case nil: String(localized: .IRC.xkqRt)
		}
	}

	static func alreadyStopped(identifier: String) -> String {
		String(localized: .IRC.ax6N9(identifier))
	}

	static func stopped(identifier: String) -> String {
		String(localized: .IRC.hs0Up(identifier))
	}

	static func restarted(identifier: String) -> String {
		String(localized: .IRC.qb7Mi(identifier))
	}

	static func cannotRestart(identifier: String) -> String {
		String(localized: .IRC.dgpD4(identifier))
	}

	static func removed(identifier: String) -> String {
		String(localized: .IRC.p7SIs(identifier))
	}

	static func notFound(identifier: String) -> String {
		String(localized: .IRC.vzuXh(identifier))
	}

	static func count(_ count: Int) -> String {
		count == 1 ? String(localized: .IRC._6TsOi(count)) : String(localized: .IRC.q1M1E(count))
	}

	static func summary(
		identifier: String,
		status: String,
		interval: String,
		nextFire: String,
		command: String
	) -> String {
		String(localized: .IRC._4N62X(identifier, status, interval, nextFire, command))
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
			localized: .IRC.uw0V2(
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
