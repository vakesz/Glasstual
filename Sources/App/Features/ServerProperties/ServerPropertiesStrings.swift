/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

nonisolated enum ServerPropertiesStrings { // nonisolated: value
	enum AddressBook {
		static func entryType(_ entryType: IRCAddressBookEntryType) -> String {
			switch entryType {
			case .ignore, .mixed:
				String(localized: .TDCServerPropertiesSheet.userIgnore)
			case .userTracking:
				String(localized: .TDCServerPropertiesSheet.userTracking)
			@unknown default:
				String(localized: .TDCServerPropertiesSheet.userIgnore)
			}
		}
	}

	enum Highlight {
		static var allChannels: String {
			String(localized: .TDCServerPropertiesSheet.allChannels)
		}

		static func matchType(isExcluded: Bool) -> String {
			isExcluded
				? String(localized: .TDCServerPropertiesSheet.serverSpecificHighlightEntryExclude)
				: String(localized: .TDCServerPropertiesSheet.serverSpecificHighlightEntryMatch)
		}
	}

	enum Navigation {
		static var serverProperties: String {
			String(localized: .TDCServerPropertiesSheet.serverProperties)
		}

		static var vendorSpecific: String {
			String(localized: .TDCServerPropertiesSheet.vendorSpecific)
		}

		static var advanced: String {
			String(localized: .TDCServerPropertiesSheet.serverPropertiesNavigationMenuAdvanced)
		}

		static var addressBook: String {
			String(localized: .TDCServerPropertiesSheet.addressBook)
		}

		static var channelList: String {
			String(localized: .TDCServerPropertiesSheet.channelList)
		}

		static var connectCommands: String {
			String(localized: .TDCServerPropertiesSheet.connectCommands)
		}

		static var encoding: String {
			String(localized: .TDCServerPropertiesSheet.serverPropertiesNavigationMenuEncoding)
		}

		static var general: String {
			String(localized: .TDCServerPropertiesSheet.serverPropertiesNavigationMenuGeneral)
		}

		static var identity: String {
			String(localized: .TDCServerPropertiesSheet.serverPropertiesNavigationMenuIdentity)
		}

		static var highlights: String {
			String(localized: .TDCServerPropertiesSheet.serverPropertiesNavigationMenuHighlights)
		}

		static var messages: String {
			String(localized: .TDCServerPropertiesSheet.serverPropertiesNavigationMenuMessages)
		}

		static var zncBouncer: String {
			String(localized: .TDCServerPropertiesSheet.zncBouncer)
		}

		static var clientCertificate: String {
			String(localized: .TDCServerPropertiesSheet.clientCertificate)
		}

		static var floodControl: String {
			String(localized: .TDCServerPropertiesSheet.floodControl)
		}

		static var networkSocket: String {
			String(localized: .TDCServerPropertiesSheet.networkSocket)
		}

		static var proxyServer: String {
			String(localized: .TDCServerPropertiesSheet.proxyServer)
		}

		static var redundancy: String {
			String(localized: .TDCServerPropertiesSheet.serverPropertiesNavigationMenuRedundancy)
		}
	}

	enum Validation {
		static var invalidUsername: String {
			String(localized: .TDCServerPropertiesSheet.pleaseEnterAProperlyFormattedUsername)
		}

		static var invalidRealName: String {
			String(localized: .TDCServerPropertiesSheet.pleaseEnterAProperlyFormattedReal)
		}

		static var invalidProxyAddress: String {
			String(localized: .TDCServerPropertiesSheet.pleaseEnterAProperlyFormattedProxy)
		}

		static func invalidAlternateNickname(_ nickname: String) -> String {
			String(localized: .TDCServerPropertiesSheet.pleaseEnterAListOfProperly(nickname))
		}
	}

	enum Certificate {
		static var noneSelected: String {
			String(localized: .TDCServerPropertiesSheet.noCertificateSelected)
		}

		static var chooseTitle: String {
			String(localized: .TDCServerPropertiesSheet.chooseAnIdentity)
		}

		static var chooseExplanation: String {
			String(localized: .TDCServerPropertiesSheet.selectACertificateToSendWhen)
		}

		static var noneAvailableTitle: String {
			String(localized: .TDCServerPropertiesSheet.noCertificatesAvailable)
		}

		static var noneAvailableExplanation: String {
			String(localized: .TDCServerPropertiesSheet.thereAreNoCertificates)
		}
	}

	enum CipherSuites {
		static func title(collectionName: String) -> String {
			String(localized: .TDCServerPropertiesSheet.includesTheFollowingCipherSuites(collectionName))
		}

		static func description(_ suites: String) -> String {
			String(localized: .TDCServerPropertiesSheet.theseCipherSuitesAreOrdered(suites))
		}
	}

	enum NickServ {
		static var missingPasswordTitle: String {
			String(localized: .TDCServerPropertiesSheet.preferenceYouHaveEnabledWillNot)
		}

		static var missingPasswordRecovery: String {
			String(localized: .TDCServerPropertiesSheet.enterYourNickservPasswordInto)
		}
	}

	enum ExternalChange {
		static var reloadTitle: String {
			String(localized: .TDCServerPropertiesSheet.thisConnectionsConfigurationHasChangedDo)
		}

		static var unsavedChangesWarning: String {
			String(localized: .TDCServerPropertiesSheet.youWillLooseUnsavedChangesIf)
		}
	}
}
