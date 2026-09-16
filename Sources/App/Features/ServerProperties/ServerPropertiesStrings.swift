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
		static func entryType(_ entryType: AddressBookEntryType) -> String {
			switch entryType {
			case .ignore, .mixed:
				String(localized: .ServerProperties.userIgnore)
			case .userTracking:
				String(localized: .ServerProperties.userTracking)
			@unknown default:
				String(localized: .ServerProperties.userIgnore)
			}
		}
	}

	/// Help tags and spoken labels for the icon-only buttons under each list.
	/// An image of a plus sign says nothing on its own.
	enum ListButton {
		static var addChannel: String {
			String(localized: .ServerProperties.addChannelButton)
		}

		static var editChannel: String {
			String(localized: .ServerProperties.editChannelButton)
		}

		static var removeChannel: String {
			String(localized: .ServerProperties.removeChannelButton)
		}

		static var addHighlight: String {
			String(localized: .ServerProperties.addHighlightButton)
		}

		static var editHighlight: String {
			String(localized: .ServerProperties.editHighlightButton)
		}

		static var removeHighlight: String {
			String(localized: .ServerProperties.removeHighlightButton)
		}

		static var addAddressBookEntry: String {
			String(localized: .ServerProperties.addAddressBookEntryButton)
		}

		static var editAddressBookEntry: String {
			String(localized: .ServerProperties.editAddressBookEntryButton)
		}

		static var removeAddressBookEntry: String {
			String(localized: .ServerProperties.removeAddressBookEntryButton)
		}
	}

	enum Highlight {
		static var allChannels: String {
			String(localized: .ServerProperties.allChannels)
		}

		static func matchType(isExcluded: Bool) -> String {
			isExcluded
				? String(localized: .ServerProperties.serverSpecificHighlightEntryExclude)
				: String(localized: .ServerProperties.serverSpecificHighlightEntryMatch)
		}
	}

	enum Navigation {
		static var connection: String {
			String(localized: .ServerProperties.navigationSectionConnection)
		}

		static var vendorSpecific: String {
			String(localized: .ServerProperties.vendorSpecific)
		}

		static var advanced: String {
			String(localized: .ServerProperties.serverPropertiesNavigationMenuAdvanced)
		}

		static var addressBook: String {
			String(localized: .ServerProperties.addressBook)
		}

		static var channelList: String {
			String(localized: .ServerProperties.channelList)
		}

		static var connectCommands: String {
			String(localized: .ServerProperties.connectCommands)
		}

		static var encoding: String {
			String(localized: .ServerProperties.serverPropertiesNavigationMenuEncoding)
		}

		static var general: String {
			String(localized: .ServerProperties.serverPropertiesNavigationMenuGeneral)
		}

		static var identity: String {
			String(localized: .ServerProperties.serverPropertiesNavigationMenuIdentity)
		}

		static var highlights: String {
			String(localized: .ServerProperties.serverPropertiesNavigationMenuHighlights)
		}

		static var messages: String {
			String(localized: .ServerProperties.serverPropertiesNavigationMenuMessages)
		}

		static var zncBouncer: String {
			String(localized: .ServerProperties.zncBouncer)
		}

		static var clientCertificate: String {
			String(localized: .ServerProperties.clientCertificate)
		}

		static var floodControl: String {
			String(localized: .ServerProperties.floodControl)
		}

		static var networkSocket: String {
			String(localized: .ServerProperties.networkSocket)
		}

		static var proxyServer: String {
			String(localized: .ServerProperties.proxyServer)
		}
	}

	/// The network list a new connection sheet opens on.
	enum Template {
		static var title: String {
			String(localized: .ServerProperties.chooseNetworkTitle)
		}

		static var help: String {
			String(localized: .ServerProperties.templatePickerHelp)
		}

		static var customServerHelp: String {
			String(localized: .ServerProperties.templateCustomServerHelp)
		}

		static var suggestedChannels: String {
			String(localized: .ServerProperties.templateSuggestedChannels)
		}

		static var suggestedChannelsHelp: String {
			String(localized: .ServerProperties.templateSuggestedChannelsHelp)
		}

		static var noSuggestedChannels: String {
			String(localized: .ServerProperties.templateNoSuggestedChannels)
		}

		static var registrationRequired: String {
			String(localized: .ServerProperties.templateRegistrationRequired)
		}

		static var website: String {
			String(localized: .ServerProperties.templateWebsite)
		}
	}

	enum General {
		static var connectionName: String {
			String(localized: .ServerProperties.connectionName)
		}

		static var serverAddress: String {
			String(localized: .ServerProperties.serverAddress)
		}

		static var serverPort: String {
			String(localized: .ServerProperties.serverPort)
		}

		/// Spoken for the Server Address field, whose completions are the bundled
		/// networks. Nothing else says the list is there.
		static var serverAddressNetworkHint: String {
			String(localized: .ServerProperties.serverAddressNetworkHint)
		}

		static var serverPassword: String {
			String(localized: .ServerProperties.serverPassword)
		}

		static var connectSecurely: String {
			String(localized: .ServerProperties.connectSecurely)
		}

		static var modifyAlternateServers: String {
			String(localized: .ServerProperties.modifyAlternateServers)
		}

		static var connectOnLaunch: String {
			String(localized: .ServerProperties.connectWhenGlasstualOpens)
		}

		static var reconnectAfterDisconnect: String {
			String(localized: .ServerProperties.reconnectAfterDisconnect)
		}

		static var disconnectWhenComputerSleeps: String {
			String(localized: .ServerProperties.disconnectWhenComputerSleeps)
		}

		static var serverPasswordHelp: String {
			String(localized: .ServerProperties.serverPasswordHelp)
		}
	}

	enum Identity {
		static var nickname: String {
			String(localized: .ServerProperties.nickname)
		}

		static var awayNickname: String {
			String(localized: .ServerProperties.awayNickname)
		}

		static var alternativeNicknames: String {
			String(localized: .ServerProperties.alternativeNicknames)
		}

		static var username: String {
			String(localized: .ServerProperties.username)
		}

		static var realName: String {
			String(localized: .ServerProperties.realName)
		}

		static var ctcpVersionReply: String {
			String(localized: .ServerProperties.ctcpVersionReply)
		}

		static var nicknamePassword: String {
			String(localized: .ServerProperties.nickservOrSaslPassword)
		}

		static var signInWithSASL: String {
			String(localized: .ServerProperties.signInWithSasl)
		}

		static var autojoinWaitsForNickServ: String {
			String(localized: .ServerProperties.autojoinWaitsForNickserv)
		}

		static var warnWhenChannelsCannotBeJoined: String {
			String(localized: .ServerProperties.warnWhenChannelsCannotBeJoined)
		}

		static var disconnectOnSASLFailure: String {
			String(localized: .ServerProperties.disconnectOnSaslFailure)
		}

		static var nicknamePasswordHelp: String {
			String(localized: .ServerProperties.nicknamePasswordHelp)
		}
	}

	enum AddressBookActions {
		static var addIgnoreEntry: String {
			String(localized: .ServerProperties.addUserIgnoreEntry)
		}

		static var addTrackingEntry: String {
			String(localized: .ServerProperties.addUserTrackingEntry)
		}
	}

	enum ConnectCommands {
		static var heading: String {
			String(localized: .ServerProperties.performCommandsOnConnect)
		}

		static var setInvisibleMode: String {
			String(localized: .ServerProperties.setInvisibleModeOnConnect)
		}

		static var runSilently: String {
			String(localized: .ServerProperties.runCommandsSilently)
		}

		static var autojoinWaitsForConnectCommands: String {
			String(localized: .ServerProperties.autojoinWaitsForConnectCommands)
		}

		static var identificationExplanation: String {
			String(localized: .ServerProperties.nickServConfirmationExplanation)
		}

		/// The stepper's label, which carries the value it is stepping.
		static func autojoinDelay(seconds: Int) -> String {
			String(localized: .ServerProperties.autojoinDelayAfterConnectCommands(seconds))
		}
	}

	enum LeavingMessages {
		static var normal: String {
			String(localized: .ServerProperties.partAndQuitMessage)
		}

		static var sleepMode: String {
			String(localized: .ServerProperties.computerSleepQuitMessage)
		}
	}

	enum Encoding {
		static var primary: String {
			String(localized: .ServerProperties.encodingPrimary)
		}

		static var fallback: String {
			String(localized: .ServerProperties.encodingFallback)
		}
	}

	enum ZNC {
		static var ignoreConfiguredAutojoin: String {
			String(localized: .ServerProperties.zncIgnoreConfiguredAutojoin)
		}

		static var ignorePlaybackNotifications: String {
			String(localized: .ServerProperties.zncIgnorePlaybackNotifications)
		}

		static var onlyPlaybackLatest: String {
			String(localized: .ServerProperties.zncOnlyPlaybackLatest)
		}

		static var versionNote: String {
			String(localized: .ServerProperties.zncVersionNote)
		}
	}

	enum Socket {
		static var connectUsing: String {
			String(localized: .ServerProperties.connectUsing)
		}

		static func addressType(_ addressType: ConnectionAddressType) -> String {
			switch addressType {
			case .default: String(localized: .ServerProperties.addressTypeAutomatic)
			case .v4: String(localized: .ServerProperties.addressTypeIpv4)
			case .v6: String(localized: .ServerProperties.addressTypeIpv6)
			}
		}

		static var validateCertificateChain: String {
			String(localized: .ServerProperties.validateServerCertificateChain)
		}

		static var performPongTimer: String {
			String(localized: .ServerProperties.periodicallyPingTheServer)
		}

		static var disconnectOnPongTimer: String {
			String(localized: .ServerProperties.disconnectOnPongTimer)
		}

		static var disconnectOnReachabilityChange: String {
			String(localized: .ServerProperties.disconnectOnReachabilityChange)
		}
	}

	enum Proxy {
		static var type: String {
			String(localized: .ServerProperties.proxyType)
		}

		static func typeName(_ type: ConnectionProxyType) -> String {
			switch type {
			case .none: String(localized: .ServerProperties.proxyTypeNone)
			case .automatic: String(localized: .ServerProperties.proxyTypeAutomatic)
			case .socks5: String(localized: .ServerProperties.proxyTypeSocks5)
			case .HTTP: String(localized: .ServerProperties.proxyTypeHttp)
			case .tor: String(localized: .ServerProperties.proxyTypeTor)
			}
		}

		static var address: String {
			String(localized: .ServerProperties.proxyAddress)
		}

		static var port: String {
			String(localized: .ServerProperties.proxyPort)
		}

		static var username: String {
			String(localized: .ServerProperties.proxyUsername)
		}

		static var password: String {
			String(localized: .ServerProperties.proxyPassword)
		}

		static var openSystemSettings: String {
			String(localized: .ServerProperties.openSystemSettings)
		}

		static var torBrowserNote: String {
			String(localized: .ServerProperties.torBrowserNote)
		}

		static var passwordHelp: String {
			String(localized: .ServerProperties.proxyPasswordHelp)
		}
	}

	enum FloodControl {
		static var messageCount: String {
			String(localized: .ServerProperties.floodControlMessageCount)
		}

		static var interval: String {
			String(localized: .ServerProperties.floodControlInterval)
		}
	}

	enum Validation {
		static var invalidUsername: String {
			String(localized: .ServerProperties.pleaseEnterAProperlyFormattedUsername)
		}

		static var invalidProxyAddress: String {
			String(localized: .ServerProperties.pleaseEnterAProperlyFormattedProxy)
		}

		static func invalidAlternateNickname(_ nickname: String) -> String {
			String(localized: .ServerProperties.pleaseEnterAListOfProperly(nickname))
		}
	}

	enum Certificate {
		static var noneSelected: String {
			String(localized: .ServerProperties.noCertificateSelected)
		}

		static var name: String {
			String(localized: .ServerProperties.certificateName)
		}

		static var fingerprintSHA512: String {
			String(localized: .ServerProperties.sha512Fingerprint)
		}

		static var fingerprintSHA256: String {
			String(localized: .ServerProperties.sha256Fingerprint)
		}

		static var fingerprintSHA1: String {
			String(localized: .ServerProperties.sha1Fingerprint)
		}

		static var select: String {
			String(localized: .ServerProperties.selectCertificate)
		}

		static var reset: String {
			String(localized: .ServerProperties.resetCertificate)
		}

		static var copyNickServCommand: String {
			String(localized: .ServerProperties.copyNickservCommand)
		}

		/// Every fingerprint has a button of its own, so each says which digest
		/// it is about rather than all three reading "Copy".
		static func copyNickServCommand(forDigest digest: String) -> String {
			String(localized: .ServerProperties.copyNickservCommandFor(digest))
		}

		static var fingerprintHelp: String {
			String(localized: .ServerProperties.certificateFingerprintHelp)
		}

		static var chooseTitle: String {
			String(localized: .ServerProperties.chooseAnIdentity)
		}

		static var chooseExplanation: String {
			String(localized: .ServerProperties.selectACertificateToSendWhen)
		}

		static var noneAvailableTitle: String {
			String(localized: .ServerProperties.noCertificatesAvailable)
		}

		static var noneAvailableExplanation: String {
			String(localized: .ServerProperties.thereAreNoCertificates)
		}
	}

	enum CipherSuites {
		static var label: String {
			String(localized: .ServerProperties.cipherSuitesLabel)
		}

		static var suiteList: String {
			String(localized: .ServerProperties.viewCipherSuites)
		}

		/// The picker's name for a collection, which is also the name the
		/// explanation under the suite list quotes.
		static func collectionName(_ collection: CipherSuiteCollection) -> String {
			switch collection {
			case .default: String(localized: .ServerProperties.cipherSuitesDefault)
			case .mozilla2017: String(localized: .ServerProperties.cipherSuitesMozilla2017)
			case .mozilla2015: String(localized: .ServerProperties.cipherSuitesMozilla2015)
			case .none: String(localized: .ServerProperties.cipherSuitesNone)
			}
		}

		static func listExplanation(collectionName: String) -> String {
			String(localized: .ServerProperties.includesTheFollowingCipherSuites(collectionName))
		}
	}

	enum ExternalChange {
		static var reloadButton: String {
			String(localized: .ServerProperties.reloadButton)
		}

		static var reloadTitle: String {
			String(localized: .ServerProperties.thisConnectionsConfigurationHasChangedDo)
		}

		static var unsavedChangesWarning: String {
			String(localized: .ServerProperties.youWillLooseUnsavedChangesIf)
		}
	}
}
