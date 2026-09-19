// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
	enum Action {
		static var accept: String {
			String(localized: .Prompts.actionTitleForAcceptingAccept)
		}

		static var cancel: String {
			String(localized: .Prompts.cancel)
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

		static var delete: String {
			String(localized: .Prompts.delete)
		}

		static var no: String {
			String(localized: .Prompts.no)
		}

		static var open: String {
			String(localized: .Prompts.open)
		}

		static var save: String {
			String(localized: .Prompts.save)
		}

		static var saveFile: String {
			String(localized: .Prompts.saveFile)
		}

		static var send: String {
			String(localized: .Prompts.send)
		}

		static var yes: String {
			String(localized: .Prompts.yes)
		}
	}

	enum Alert {
		/// The standard macOS wording, used when an alert offers suppression
		/// without naming the checkbox itself.
		static var doNotAskAgain: String {
			String(localized: .Prompts.doNotAskMeAgain)
		}
	}

	enum Application {
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

	enum Deletion {
		/// Names what is about to be deleted: a confirmation that says only
		/// "the selection" leaves the reader to work out what they clicked.
		static func confirmationTitle(named name: String) -> String {
			String(localized: .Prompts.doYouWantToDeleteNamed(name))
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
		static func body(sender: String) -> String {
			String(localized: .Prompts.wantsToStartADirectChat(sender))
		}

		static func title(sender: String) -> String {
			String(localized: .Prompts.directChatRequest(sender))
		}
	}

	enum DocumentImport {
		static func scriptCommandBody(name: String) -> String {
			String(localized: .Prompts.typeIntoTheMainInputText(name))
		}

		static func scriptInstalledTitle(name: String) -> String {
			String(localized: .Prompts.scriptNamedHasBeenSuccessfullyInstalled(name))
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

		static var scrollbackFailureBody: String {
			String(localized: .Prompts.scrollbackDatabaseCouldNotBeOpened)
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

	enum TransportSecurity {
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

		static func trustFailure(_ description: String) -> String {
			String(localized: .Prompts.certificateWasNotTrusted(description))
		}
	}

	enum VirtualHost {
		static var body: String {
			String(localized: .Prompts.pleaseEnterDesiredVhostEG)
		}

		static var placeholder: String {
			String(localized: .Prompts.vhostPlaceholder)
		}

		static var title: String {
			String(localized: .Prompts.setUserVhost)
		}
	}
}
