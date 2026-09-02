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

import CocoaExtensions
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

	enum General {
		static var connectionName: String {
			String(localized: .TDCServerPropertiesSheet.connectionName)
		}

		static var serverAddress: String {
			String(localized: .TDCServerPropertiesSheet.serverAddress)
		}

		static var serverPort: String {
			String(localized: .TDCServerPropertiesSheet.serverPort)
		}

		static var serverPassword: String {
			String(localized: .TDCServerPropertiesSheet.serverPassword)
		}

		static var connectSecurely: String {
			String(localized: .TDCServerPropertiesSheet.connectSecurely)
		}

		static var modifyAlternateServers: String {
			String(localized: .TDCServerPropertiesSheet.modifyAlternateServers)
		}

		static var connectOnLaunch: String {
			String(localized: .TDCServerPropertiesSheet.connectWhenGlasstualOpens)
		}

		static var reconnectAfterDisconnect: String {
			String(localized: .TDCServerPropertiesSheet.reconnectAfterDisconnect)
		}

		static var disconnectWhenComputerSleeps: String {
			String(localized: .TDCServerPropertiesSheet.disconnectWhenComputerSleeps)
		}
	}

	enum Identity {
		static var nickname: String {
			String(localized: .TDCServerPropertiesSheet.nickname)
		}

		static var awayNickname: String {
			String(localized: .TDCServerPropertiesSheet.awayNickname)
		}

		static var alternativeNicknames: String {
			String(localized: .TDCServerPropertiesSheet.alternativeNicknames)
		}

		static var username: String {
			String(localized: .TDCServerPropertiesSheet.username)
		}

		static var realName: String {
			String(localized: .TDCServerPropertiesSheet.realName)
		}

		static var ctcpVersionReply: String {
			String(localized: .TDCServerPropertiesSheet.ctcpVersionReply)
		}

		static var nicknamePassword: String {
			String(localized: .TDCServerPropertiesSheet.nickservOrSaslPassword)
		}

		static var autojoinWaitsForNickServ: String {
			String(localized: .TDCServerPropertiesSheet.autojoinWaitsForNickserv)
		}

		static var warnWhenChannelsCannotBeJoined: String {
			String(localized: .TDCServerPropertiesSheet.warnWhenChannelsCannotBeJoined)
		}

		static var disconnectOnSASLFailure: String {
			String(localized: .TDCServerPropertiesSheet.disconnectOnSaslFailure)
		}
	}

	enum ChannelList {
		static var joinOnConnect: String {
			String(localized: .TDCServerPropertiesSheet.joinOnConnect)
		}
	}

	enum AddressBookActions {
		static var addIgnoreEntry: String {
			String(localized: .TDCServerPropertiesSheet.addUserIgnoreEntry)
		}

		static var addTrackingEntry: String {
			String(localized: .TDCServerPropertiesSheet.addUserTrackingEntry)
		}
	}

	enum ConnectCommands {
		static var heading: String {
			String(localized: .TDCServerPropertiesSheet.performCommandsOnConnect)
		}

		static var setInvisibleMode: String {
			String(localized: .TDCServerPropertiesSheet.setInvisibleModeOnConnect)
		}

		static var runSilently: String {
			String(localized: .TDCServerPropertiesSheet.runCommandsSilently)
		}

		static var autojoinWaitsForConnectCommands: String {
			String(localized: .TDCServerPropertiesSheet.autojoinWaitsForConnectCommands)
		}

		/// The stepper's label, which carries the value it is stepping.
		static func autojoinDelay(seconds: Int) -> String {
			String(localized: .TDCServerPropertiesSheet.autojoinDelayAfterConnectCommands(seconds))
		}
	}

	enum LeavingMessages {
		static var normal: String {
			String(localized: .TDCServerPropertiesSheet.partAndQuitMessage)
		}

		static var sleepMode: String {
			String(localized: .TDCServerPropertiesSheet.computerSleepQuitMessage)
		}
	}

	enum Encoding {
		static var primary: String {
			String(localized: .TDCServerPropertiesSheet.encodingPrimary)
		}

		static var fallback: String {
			String(localized: .TDCServerPropertiesSheet.encodingFallback)
		}
	}

	enum ZNC {
		static var ignoreConfiguredAutojoin: String {
			String(localized: .TDCServerPropertiesSheet.zncIgnoreConfiguredAutojoin)
		}

		static var ignorePlaybackNotifications: String {
			String(localized: .TDCServerPropertiesSheet.zncIgnorePlaybackNotifications)
		}

		static var onlyPlaybackLatest: String {
			String(localized: .TDCServerPropertiesSheet.zncOnlyPlaybackLatest)
		}

		static var versionNote: String {
			String(localized: .TDCServerPropertiesSheet.zncVersionNote)
		}
	}

	enum Socket {
		static var connectUsing: String {
			String(localized: .TDCServerPropertiesSheet.connectUsing)
		}

		static func addressType(_ addressType: IRCConnectionAddressType) -> String {
			switch addressType {
			case .default: String(localized: .TDCServerPropertiesSheet.addressTypeAutomatic)
			case .v4: String(localized: .TDCServerPropertiesSheet.addressTypeIpv4)
			case .v6: String(localized: .TDCServerPropertiesSheet.addressTypeIpv6)
			}
		}

		static var validateCertificateChain: String {
			String(localized: .TDCServerPropertiesSheet.validateServerCertificateChain)
		}

		static var performPongTimer: String {
			String(localized: .TDCServerPropertiesSheet.periodicallyPingTheServer)
		}

		static var disconnectOnPongTimer: String {
			String(localized: .TDCServerPropertiesSheet.disconnectOnPongTimer)
		}

		static var disconnectOnReachabilityChange: String {
			String(localized: .TDCServerPropertiesSheet.disconnectOnReachabilityChange)
		}
	}

	enum Proxy {
		static var type: String {
			String(localized: .TDCServerPropertiesSheet.proxyType)
		}

		static func typeName(_ type: IRCConnectionProxyType) -> String {
			switch type {
			case .none: String(localized: .TDCServerPropertiesSheet.proxyTypeNone)
			case .automatic: String(localized: .TDCServerPropertiesSheet.proxyTypeAutomatic)
			case .socks5: String(localized: .TDCServerPropertiesSheet.proxyTypeSocks5)
			case .HTTP: String(localized: .TDCServerPropertiesSheet.proxyTypeHttp)
			case .tor: String(localized: .TDCServerPropertiesSheet.proxyTypeTor)
			}
		}

		static var address: String {
			String(localized: .TDCServerPropertiesSheet.proxyAddress)
		}

		static var port: String {
			String(localized: .TDCServerPropertiesSheet.proxyPort)
		}

		static var username: String {
			String(localized: .TDCServerPropertiesSheet.proxyUsername)
		}

		static var password: String {
			String(localized: .TDCServerPropertiesSheet.proxyPassword)
		}

		static var openSystemSettings: String {
			String(localized: .TDCServerPropertiesSheet.openSystemSettings)
		}

		static var torBrowserNote: String {
			String(localized: .TDCServerPropertiesSheet.torBrowserNote)
		}
	}

	enum FloodControl {
		static var messageCount: String {
			String(localized: .TDCServerPropertiesSheet.floodControlMessageCount)
		}

		static var interval: String {
			String(localized: .TDCServerPropertiesSheet.floodControlInterval)
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

		static var name: String {
			String(localized: .TDCServerPropertiesSheet.certificateName)
		}

		static var fingerprintSHA512: String {
			String(localized: .TDCServerPropertiesSheet.sha512Fingerprint)
		}

		static var fingerprintSHA256: String {
			String(localized: .TDCServerPropertiesSheet.sha256Fingerprint)
		}

		static var fingerprintSHA1: String {
			String(localized: .TDCServerPropertiesSheet.sha1Fingerprint)
		}

		static var select: String {
			String(localized: .TDCServerPropertiesSheet.selectCertificate)
		}

		static var reset: String {
			String(localized: .TDCServerPropertiesSheet.resetCertificate)
		}

		static var copyFingerprint: String {
			String(localized: .TDCServerPropertiesSheet.copyFingerprint)
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
		static var label: String {
			String(localized: .TDCServerPropertiesSheet.cipherSuitesLabel)
		}

		static var viewList: String {
			String(localized: .TDCServerPropertiesSheet.viewCipherSuites)
		}

		/// The picker's name for a collection, which is also the name the
		/// "includes the following cipher suites" alert quotes.
		static func collectionName(_ collection: CipherSuiteCollection) -> String {
			switch collection {
			case .default: String(localized: .TDCServerPropertiesSheet.cipherSuitesDefault)
			case .mozilla2017: String(localized: .TDCServerPropertiesSheet.cipherSuitesMozilla2017)
			case .mozilla2015: String(localized: .TDCServerPropertiesSheet.cipherSuitesMozilla2015)
			case .none: String(localized: .TDCServerPropertiesSheet.cipherSuitesNone)
			}
		}

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
