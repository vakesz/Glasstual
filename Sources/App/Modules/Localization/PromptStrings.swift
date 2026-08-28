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

enum PromptDeletionTarget: Sendable {
	case channel
	case query
	case server
}

enum PromptCipherStatus: Sendable {
	case current
	case deprecated
}

/// Semantic access to the application-wide prompts retained in `Prompts.xcstrings`.
nonisolated enum PromptStrings {
	nonisolated enum Action {
		static var accept: String {
			String(localized: .Prompts.qpvGo)
		}

		static var cancel: String {
			String(localized: .Prompts.qso2G)
		}

		static var chooseFile: String {
			String(localized: .Prompts._5026H)
		}

		static var close: String {
			String(localized: .Prompts.aqwQ1)
		}

		static var confirmation: String {
			String(localized: .Prompts.c7SDq)
		}

		static var continueAction: String {
			String(localized: .Prompts.zjwBd)
		}

		static var decline: String {
			String(localized: .Prompts.dccC5)
		}

		static var no: String {
			String(localized: .Prompts._99QGg)
		}

		static var save: String {
			String(localized: .Prompts._6HxNi)
		}

		static var select: String {
			String(localized: .Prompts.xne79)
		}

		static var yes: String {
			String(localized: .Prompts.mvhMs)
		}
	}

	nonisolated enum Alert {
		static var doNotShowAgain: String {
			String(localized: .Prompts._68UZ9)
		}
	}

	nonisolated enum Application {
		static var continueWithAnotherInstanceBody: String {
			String(localized: .Prompts.kx4Q8)
		}

		static var continueWithAnotherInstanceTitle: String {
			String(localized: .Prompts.hcb3I)
		}

		static var quitBody: String {
			String(localized: .Prompts._77UVp)
		}

		static var quitButtonTitle: String {
			String(localized: .Prompts._1BfK0)
		}

		static var quitTitle: String {
			String(localized: .Prompts._6Vj2P)
		}
	}

	nonisolated enum ConfigurationTransfer {
		static var exportBody: String {
			String(localized: .Prompts.sypAl)
		}

		static var exportButtonTitle: String {
			String(localized: .Prompts.vunF0)
		}

		static var exportTitle: String {
			String(localized: .Prompts._1FmUp)
		}

		static var importBody: String {
			String(localized: .Prompts.jsh1A)
		}

		static var importTitle: String {
			String(localized: .Prompts.itb3X)
		}
	}

	nonisolated enum ConnectionLink {
		static var createNewConnectionButtonTitle: String {
			String(localized: .Prompts.xca5H)
		}

		static var useExistingConnectionButtonTitle: String {
			String(localized: .Prompts.sl5Rf)
		}

		static func existingConnectionBody(name: String, includesMultipleChannels: Bool) -> String {
			if includesMultipleChannels {
				return String(localized: .Prompts.a9Z9F(name))
			}
			return String(localized: .Prompts.mx1Qz(name))
		}

		static func title(serverAddress: String, channelNames: String, includesMultipleChannels: Bool) -> String {
			if includesMultipleChannels {
				return String(localized: .Prompts.pncEw(serverAddress, channelNames))
			}
			return String(localized: .Prompts._3L63Z(serverAddress, channelNames))
		}
	}

	nonisolated enum DataMigration {
		static var copiedContentTitle: String {
			String(localized: .Prompts.iosNa)
		}

		static var removeOldContentBody: String {
			String(localized: .Prompts.qy45O)
		}

		static var removeOldContentButtonTitle: String {
			String(localized: .Prompts.q3T45)
		}
	}

	nonisolated enum Deletion {
		static var confirmationTitle: String {
			String(localized: .Prompts._0KzWd)
		}

		static func warning(for target: PromptDeletionTarget) -> String {
			switch target {
			case .channel:
				String(localized: .Prompts._516Ms)
			case .query:
				String(localized: .Prompts._61SJc)
			case .server:
				String(localized: .Prompts.etlSs)
			}
		}

		static func existingQueryTitle(name: String) -> String {
			String(localized: .Prompts.d2276(name))
		}
	}

	nonisolated enum DirectChat {
		static var acceptButtonTitle: String {
			Action.accept
		}

		static var declineButtonTitle: String {
			Action.decline
		}

		static func body(sender: String) -> String {
			String(localized: .Prompts.dccC2(sender))
		}

		static func title(sender: String) -> String {
			String(localized: .Prompts.dccC3(sender))
		}
	}

	nonisolated enum DocumentImport {
		static var documentOpenBody: String {
			String(localized: .Prompts._6TjYp)
		}

		static var extensionRestartBody: String {
			String(localized: .Prompts.k69Q0)
		}

		static var scriptSaveErrorBody: String {
			String(localized: .Prompts.ztuNv)
		}

		static var scriptSaveErrorTitle: String {
			String(localized: .Prompts.m2RGv)
		}

		static func documentOpenTitle(filename: String) -> String {
			String(localized: .Prompts.xfl8E(filename))
		}

		static func extensionInstalledTitle(name: String) -> String {
			String(localized: .Prompts.xek0T(name))
		}

		static func scriptCommandBody(name: String) -> String {
			String(localized: .Prompts._3ZeXh(name))
		}

		static func scriptInstalledTitle(name: String) -> String {
			String(localized: .Prompts._4UaV5(name))
		}

		static func scriptSavePanelBody(bundleIdentifier: String) -> String {
			String(localized: .Prompts._0BjIc(bundleIdentifier))
		}
	}

	nonisolated enum ExternalApplication {
		static func body(url: String) -> String {
			String(localized: .Prompts._5OqVv(url))
		}

		static func title(applicationName: String) -> String {
			String(localized: .Prompts._2UlCl(applicationName))
		}
	}

	nonisolated enum InlineMedia {
		static var body: String {
			String(localized: .Prompts.vcqSz)
		}

		static var openSystemSettingsButtonTitle: String {
			String(localized: .Prompts.x3EUr)
		}

		static var title: String {
			String(localized: .Prompts._82QZi)
		}

		static var turnOnButtonTitle: String {
			String(localized: .Prompts.xkjNw)
		}
	}

	nonisolated enum Logging {
		static var disabledForLowStorageTitle: String {
			String(localized: .Prompts.bi7Ah)
		}

		static var emptyAlertBody: String {
			String(localized: .Prompts.f05Hu)
		}

		static var noLogsTitle: String {
			String(localized: .Prompts.k5519)
		}

		static var resumeAfterLowStorageBody: String {
			String(localized: .Prompts.v9EJy)
		}

		static var scrollbackFailureTitle: String {
			String(localized: .Prompts.h993Q)
		}

		static var staleLocationBody: String {
			String(localized: .Prompts.atn1C)
		}

		static var staleLocationTitle: String {
			String(localized: .Prompts.b7OV4)
		}

		static func lastError(_ description: String) -> String {
			String(localized: .Prompts.nlzUm(description))
		}
	}

	nonisolated enum Plugin {
		static var incompatibleReminderButtonTitle: String {
			String(localized: .Prompts._3245D)
		}

		static var unsignedBody: String {
			String(localized: .Prompts.t8Y4P)
		}

		static var viewFilesButtonTitle: String {
			String(localized: .Prompts._0IkO9)
		}

		static func incompatibleBody(minimumVersion: String) -> String {
			String(localized: .Prompts._45ADf(minimumVersion))
		}

		static func incompatibleTitle(pluginNames: String) -> String {
			String(localized: .Prompts.af645(pluginNames))
		}

		static func unsignedTitle(pluginNames: String) -> String {
			String(localized: .Prompts.j6C1V(pluginNames))
		}
	}

	nonisolated enum TextSearch {
		static var body: String {
			String(localized: .Prompts.d2W4O)
		}

		static var buttonTitle: String {
			String(localized: .Prompts.q5HXx)
		}

		static var title: String {
			String(localized: .Prompts.akrEh)
		}
	}

	nonisolated enum Theme {
		static var chooseDifferentStyleButtonTitle: String {
			String(localized: .Prompts._2A35S)
		}

		static var incompatibleBody: String {
			String(localized: .Prompts._76TPn)
		}

		static var keepLightButtonTitle: String {
			String(localized: .Prompts.hf0W3)
		}

		static var modifiedBody: String {
			String(localized: .Prompts._3WdGj)
		}

		static var switchToDarkButtonTitle: String {
			String(localized: .Prompts.hv079)
		}

		static var wantsDarkAppearanceBody: String {
			String(localized: .Prompts._1936O)
		}

		static func incompatibleTitle(name: String) -> String {
			String(localized: .Prompts.py0Cr(name))
		}

		static func modifiedTitle(name: String) -> String {
			String(localized: .Prompts.fjwHj(name))
		}

		static func wantsDarkAppearanceTitle(name: String) -> String {
			String(localized: .Prompts.eznRm(name))
		}
	}

	nonisolated enum TransportSecurity {
		static var invalidCertificateContinueButtonTitle: String {
			Action.continueAction
		}

		static func certificateFailureBody(serverName: String) -> String {
			String(localized: .Prompts._85ZQw(serverName))
		}

		static func certificateFailureTitle(serverName: String) -> String {
			String(localized: .Prompts.m8B58(serverName))
		}

		static func certificateSummary(
			policyName: String,
			cipherSummary: String
		) -> String {
			String(localized: .Prompts.iun45(policyName, cipherSummary))
		}

		static func cipherSummary(
			policyName: String,
			cipherSuite: String,
			status: PromptCipherStatus
		) -> String {
			switch status {
			case .current:
				String(localized: .Prompts._2JqT5(policyName, cipherSuite))
			case .deprecated:
				String(localized: .Prompts._8OuPu(policyName, cipherSuite))
			}
		}

		static func encryptedConnectionTitle(policyName: String) -> String {
			String(localized: .Prompts.sfxXx(policyName))
		}

		static func encryptionDescription(policyName: String) -> String {
			String(localized: .Prompts.ihyMz(policyName))
		}

		static func trustFailure(_ description: String) -> String {
			String(localized: .Prompts.k3TVq(description))
		}
	}

	nonisolated enum VirtualHost {
		static var body: String {
			String(localized: .Prompts._2MxJf)
		}

		static var title: String {
			String(localized: .Prompts._7GrE4)
		}
	}

	nonisolated enum WebInspector {
		static var unavailableBody: String {
			String(localized: .Prompts.kigM1)
		}

		static var unavailableTitle: String {
			String(localized: .Prompts.ujw64)
		}
	}
}
