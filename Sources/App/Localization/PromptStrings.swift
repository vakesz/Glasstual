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
nonisolated enum PromptStrings { // nonisolated: value
	enum Action {
		static var accept: String {
			String(localized: .Prompts.actionTitleForAcceptingAccept)
		}

		static var cancel: String {
			String(localized: .Prompts.cancel)
		}

		static var chooseFile: String {
			String(localized: .Prompts.chooseFile)
		}

		static var close: String {
			String(localized: .Prompts.close)
		}

		static var confirmation: String {
			String(localized: .Prompts.genericAcknowledgementButtonTitleOk)
		}

		static var continueAction: String {
			String(localized: .Prompts.continue)
		}

		static var decline: String {
			String(localized: .Prompts.directChatDccChatDecline)
		}

		static var no: String {
			String(localized: .Prompts.no)
		}

		static var save: String {
			String(localized: .Prompts.save)
		}

		static var select: String {
			String(localized: .Prompts.select)
		}

		static var yes: String {
			String(localized: .Prompts.yes)
		}
	}

	enum Alert {
		static var doNotShowAgain: String {
			String(localized: .Prompts.doNotShowThisMessageAgain)
		}
	}

	enum Application {
		static var continueWithAnotherInstanceBody: String {
			String(localized: .Prompts.areYouSureYouWantToContinue)
		}

		static var continueWithAnotherInstanceTitle: String {
			String(localized: .Prompts.preferencesMayBecomeCorruptedIf)
		}

		static var quitBody: String {
			String(localized: .Prompts.quittingWillDisconnectYouFromAny)
		}

		static var quitButtonTitle: String {
			String(localized: .Prompts.quit)
		}

		static var quitTitle: String {
			String(localized: .Prompts.areYouSureYouWantToQuitGlasstual)
		}
	}

	enum ConfigurationTransfer {
		static var exportBody: String {
			String(localized: .Prompts.pleaseNoteThatTheFollowingItemsCannotBeExported)
		}

		static var exportButtonTitle: String {
			String(localized: .Prompts.saveFile)
		}

		static var exportTitle: String {
			String(localized: .Prompts.thisActionWillSaveACopy)
		}

		static var importBody: String {
			String(localized: .Prompts.pleaseNoteThatTheFollowingItems)
		}

		static var importTitle: String {
			String(localized: .Prompts.thisActionWillOverwriteYourConfiguration)
		}
	}

	enum ConnectionLink {
		static var createNewConnectionButtonTitle: String {
			String(localized: .Prompts.createNewConnection)
		}

		static var useExistingConnectionButtonTitle: String {
			String(localized: .Prompts.useExistingConnection)
		}

		static func existingConnectionBody(name: String, includesMultipleChannels: Bool) -> String {
			if includesMultipleChannels {
				return String(localized: .Prompts.connectionNamedIsAlreadyConfigured(name))
			}
			return String(localized: .Prompts.connectionNamedIsAlreadyConfiguredToConnectTo(name))
		}

		static func title(serverAddress: String, channelNames: String, includesMultipleChannels: Bool) -> String {
			if includesMultipleChannels {
				return String(localized: .Prompts.youHaveClickedALinkThatWillConnect(serverAddress, channelNames))
			}
			return String(localized: .Prompts.youHaveClickedALink(serverAddress, channelNames))
		}
	}

	enum DataMigration {
		static var copiedContentTitle: String {
			String(localized: .Prompts.glasstualHasCopiedTheFollowingContent)
		}

		static var removeOldContentBody: String {
			String(localized: .Prompts.cachesCustomAddonsCustomStylesPreferences)
		}

		static var removeOldContentButtonTitle: String {
			String(localized: .Prompts.iWouldLikeToRemove)
		}
	}

	enum Deletion {
		static var confirmationTitle: String {
			String(localized: .Prompts.doYouWantToDelete)
		}

		static func warning(for target: PromptDeletionTarget) -> String {
			switch target {
			case .channel:
				String(localized: .Prompts.thereIsNoUndoAndAll)
			case .query:
				String(localized: .Prompts.thereIsNoUndoAndAllDataRelated)
			case .server:
				String(localized: .Prompts.thereIsNoUndoAndAll2)
			}
		}

		static func existingQueryTitle(name: String) -> String {
			String(localized: .Prompts.queryNamedAlreadyExistsDo(name))
		}
	}

	enum DirectChat {
		static var acceptButtonTitle: String {
			Action.accept
		}

		static var declineButtonTitle: String {
			Action.decline
		}

		static func body(sender: String) -> String {
			String(localized: .Prompts.wantsToStartADirectChat(sender))
		}

		static func title(sender: String) -> String {
			String(localized: .Prompts.directChatRequest(sender))
		}
	}

	enum DocumentImport {
		static var documentOpenBody: String {
			String(localized: .Prompts.intentionallyEmptyInformativeText)
		}

		static var extensionRestartBody: String {
			String(localized: .Prompts.restartGlasstualToLoadThisExtension)
		}

		static var scriptSaveErrorBody: String {
			String(localized: .Prompts.intentionallyEmptyRecoverySuggestion)
		}

		static var scriptSaveErrorTitle: String {
			String(localized: .Prompts.scriptCannotBeSavedHere)
		}

		static func documentOpenTitle(filename: String) -> String {
			String(localized: .Prompts.areYouSureYouWantToOpenTheFileNamed(filename))
		}

		static func extensionInstalledTitle(name: String) -> String {
			String(localized: .Prompts.extensionNamedHasBeenSuccessfullyInstalled(name))
		}

		static func scriptCommandBody(name: String) -> String {
			String(localized: .Prompts.typeIntoTheMainInputText(name))
		}

		static func scriptInstalledTitle(name: String) -> String {
			String(localized: .Prompts.scriptNamedHasBeenSuccessfullyInstalled(name))
		}

		static func scriptSavePanelBody(bundleIdentifier: String) -> String {
			String(localized: .Prompts.toInstallThisScriptSave(bundleIdentifier))
		}
	}

	enum ExternalApplication {
		static func body(url: String) -> String {
			String(localized: .Prompts.areYouSureYouWant(url))
		}

		static func title(applicationName: String) -> String {
			String(localized: .Prompts.youHaveClickedOnALink(applicationName))
		}
	}

	enum InlineMedia {
		static var body: String {
			String(localized: .Prompts.inlineMediaDoesNotUse)
		}

		static var openSystemSettingsButtonTitle: String {
			String(localized: .Prompts.openSystemSettings)
		}

		static var title: String {
			String(localized: .Prompts.areYouSureYouWish)
		}

		static var turnOnButtonTitle: String {
			String(localized: .Prompts.turn)
		}
	}

	enum Logging {
		static var disabledForLowStorageTitle: String {
			String(localized: .Prompts.loggingHasBeenDisabledBecauseThere)
		}

		static var emptyAlertBody: String {
			String(localized: .Prompts.intentionallyEmptyInformativeTextForTheNoLogs)
		}

		static var noLogsTitle: String {
			String(localized: .Prompts.noLogsWereFound)
		}

		static var resumeAfterLowStorageBody: String {
			String(localized: .Prompts.loggingWillResumeWhenThere)
		}

		static var scrollbackFailureTitle: String {
			String(localized: .Prompts.processResponsibleForManagingScrollback)
		}

		static var staleLocationBody: String {
			String(localized: .Prompts.navigateToPreferencesAdvancedLogLocation)
		}

		static var staleLocationTitle: String {
			String(localized: .Prompts.glasstualIsUnableToAccess)
		}

		static func lastError(_ description: String) -> String {
			String(localized: .Prompts.lastKnownErrorMessage(description))
		}
	}

	enum Plugin {
		static var incompatibleReminderButtonTitle: String {
			String(localized: .Prompts.remindMeNextLaunch)
		}

		static var unsignedBody: String {
			String(localized: .Prompts.pluginsInstalledOutsideOfGlasstualMust)
		}

		static var viewFilesButtonTitle: String {
			String(localized: .Prompts.viewFiles)
		}

		static func incompatibleBody(minimumVersion: String) -> String {
			String(localized: .Prompts.pleaseContactTheDeveloperOfEach(minimumVersion))
		}

		static func incompatibleTitle(pluginNames: String) -> String {
			String(localized: .Prompts.versionOfGlasstual(pluginNames))
		}

		static func unsignedTitle(pluginNames: String) -> String {
			String(localized: .Prompts.glasstualRefusedToLoadTheseAddons(pluginNames))
		}
	}

	enum TextSearch {
		static var body: String {
			String(localized: .Prompts.keyboardShortcutGCanBeUsed)
		}

		static var buttonTitle: String {
			String(localized: .Prompts.search)
		}

		static var title: String {
			String(localized: .Prompts.enterSomeTextToSearch)
		}
	}

	enum Theme {
		static var chooseDifferentStyleButtonTitle: String {
			String(localized: .Prompts.chooseDifferentStyle)
		}

		static var incompatibleBody: String {
			String(localized: .Prompts.someFeaturesWillNotWorkCorrectly)
		}

		static var keepLightButtonTitle: String {
			String(localized: .Prompts.keepItLight)
		}

		static var modifiedBody: String {
			String(localized: .Prompts.thisUsuallyOccursWhenOne)
		}

		static var switchToDarkButtonTitle: String {
			String(localized: .Prompts.paintItBlack)
		}

		static var wantsDarkAppearanceBody: String {
			String(localized: .Prompts.doYouWantToKeepGlasstuals)
		}

		static func incompatibleTitle(name: String) -> String {
			String(localized: .Prompts.styleNamedIsNotDesigned(name))
		}

		static func modifiedTitle(name: String) -> String {
			String(localized: .Prompts.styleNamedHasBeenModified(name))
		}

		static func wantsDarkAppearanceTitle(name: String) -> String {
			String(localized: .Prompts.styleNamedWantsToEnableDark(name))
		}
	}

	enum TransportSecurity {
		static var invalidCertificateContinueButtonTitle: String {
			Action.continueAction
		}

		static func certificateFailureBody(serverName: String) -> String {
			String(localized: .Prompts.certificateForThisServerIsInvalid(serverName))
		}

		static func certificateFailureTitle(serverName: String) -> String {
			String(localized: .Prompts.glasstualCantVerifyTheIdentity(serverName))
		}

		static func certificateSummary(
			policyName: String,
			cipherSummary: String
		) -> String {
			String(localized: .Prompts.encryptionWithADigitalCertificateKeepsInformation(policyName, cipherSummary))
		}

		static func cipherSummary(
			policyName: String,
			cipherSuite: String,
			status: PromptCipherStatus
		) -> String {
			switch status {
			case .current:
				String(localized: .Prompts.withTheCipherSuite(policyName, cipherSuite))
			case .deprecated:
				String(localized: .Prompts.withTheCipherSuiteDeprecated(policyName, cipherSuite))
			}
		}

		static func encryptedConnectionTitle(policyName: String) -> String {
			String(localized: .Prompts.glasstualIsUsingAnEncryptedConnection(policyName))
		}

		static func encryptionDescription(policyName: String) -> String {
			String(localized: .Prompts.encryptionWithADigitalCertificateKeeps(policyName))
		}

		static func trustFailure(_ description: String) -> String {
			String(localized: .Prompts.certificateWasNotTrusted(description))
		}
	}

	enum VirtualHost {
		static var body: String {
			String(localized: .Prompts.pleaseEnterDesiredVhostEG)
		}

		static var title: String {
			String(localized: .Prompts.setUserVhost)
		}
	}

	enum WebInspector {
		static var unavailableBody: String {
			String(localized: .Prompts.disableWebkit2OrUpgrade)
		}

		static var unavailableTitle: String {
			String(localized: .Prompts.inspectElementFeatureOfWebkit2Cannot)
		}
	}
}
