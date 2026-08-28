/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

nonisolated enum ServerPropertiesStrings {
	nonisolated enum AddressBook {
		static func entryType(_ entryType: IRCAddressBookEntryType) -> String {
			switch entryType {
			case .ignore, .mixed:
				String(localized: .TDCServerPropertiesSheet.f7OX4)
			case .userTracking:
				String(localized: .TDCServerPropertiesSheet.b0G0X)
			@unknown default:
				String(localized: .TDCServerPropertiesSheet.f7OX4)
			}
		}
	}

	nonisolated enum Highlight {
		static var allChannels: String {
			String(localized: .TDCServerPropertiesSheet._61F6B)
		}

		static func matchType(isExcluded: Bool) -> String {
			isExcluded
				? String(localized: .TDCServerPropertiesSheet.qccB4)
				: String(localized: .TDCServerPropertiesSheet.tetDk)
		}
	}

	nonisolated enum Navigation {
		static var serverProperties: String {
			String(localized: .TDCServerPropertiesSheet.lwwPc)
		}

		static var vendorSpecific: String {
			String(localized: .TDCServerPropertiesSheet.v278W)
		}

		static var advanced: String {
			String(localized: .TDCServerPropertiesSheet._8UwTz)
		}

		static var addressBook: String {
			String(localized: .TDCServerPropertiesSheet._8Zc6Y)
		}

		static var channelList: String {
			String(localized: .TDCServerPropertiesSheet._5Oz07)
		}

		static var connectCommands: String {
			String(localized: .TDCServerPropertiesSheet.hip13)
		}

		static var encoding: String {
			String(localized: .TDCServerPropertiesSheet._8UgKa)
		}

		static var general: String {
			String(localized: .TDCServerPropertiesSheet.ehx4D)
		}

		static var identity: String {
			String(localized: .TDCServerPropertiesSheet._8IkQo)
		}

		static var highlights: String {
			String(localized: .TDCServerPropertiesSheet.jtxHn)
		}

		static var messages: String {
			String(localized: .TDCServerPropertiesSheet.j34Yr)
		}

		static var zncBouncer: String {
			String(localized: .TDCServerPropertiesSheet.fsj7F)
		}

		static var clientCertificate: String {
			String(localized: .TDCServerPropertiesSheet.ce7Kc)
		}

		static var floodControl: String {
			String(localized: .TDCServerPropertiesSheet.fcrW8)
		}

		static var networkSocket: String {
			String(localized: .TDCServerPropertiesSheet.ffyXt)
		}

		static var proxyServer: String {
			String(localized: .TDCServerPropertiesSheet.t527A)
		}

		static var redundancy: String {
			String(localized: .TDCServerPropertiesSheet._36NU9)
		}
	}

	nonisolated enum Validation {
		static var invalidUsername: String {
			String(localized: .TDCServerPropertiesSheet._8IwQ8)
		}

		static var invalidRealName: String {
			String(localized: .TDCServerPropertiesSheet.agyBp)
		}

		static var invalidProxyAddress: String {
			String(localized: .TDCServerPropertiesSheet.tloB6)
		}

		static func invalidAlternateNickname(_ nickname: String) -> String {
			String(localized: .TDCServerPropertiesSheet.wlzTb(nickname))
		}
	}

	nonisolated enum Certificate {
		static var noneSelected: String {
			String(localized: .TDCServerPropertiesSheet._6XzEc)
		}

		static var chooseTitle: String {
			String(localized: .TDCServerPropertiesSheet._6WqI4)
		}

		static var chooseExplanation: String {
			String(localized: .TDCServerPropertiesSheet.mi4Fd)
		}

		static var noneAvailableTitle: String {
			String(localized: .TDCServerPropertiesSheet.pmkOs)
		}

		static var noneAvailableExplanation: String {
			String(localized: .TDCServerPropertiesSheet._489HG)
		}
	}

	nonisolated enum CipherSuites {
		static func title(collectionName: String) -> String {
			String(localized: .TDCServerPropertiesSheet.yko5G(collectionName))
		}

		static func description(_ suites: String) -> String {
			String(localized: .TDCServerPropertiesSheet.k508N(suites))
		}
	}

	nonisolated enum NickServ {
		static var missingPasswordTitle: String {
			String(localized: .TDCServerPropertiesSheet._94REq)
		}

		static var missingPasswordRecovery: String {
			String(localized: .TDCServerPropertiesSheet._26UJ8)
		}
	}

	nonisolated enum ExternalChange {
		static var reloadTitle: String {
			String(localized: .TDCServerPropertiesSheet.bzhIl)
		}

		static var unsavedChangesWarning: String {
			String(localized: .TDCServerPropertiesSheet.oz4Kb)
		}
	}
}
