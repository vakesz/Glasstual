/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// Shared, stateless presentation for credential failures in editors and at
/// shutdown. The persistence service receives its presenter from the application.
enum KeychainAlerts {
	static func terminationFailureAlert(_ error: any Error) -> AlertRequest {
		AlertRequest(
			title: String(localized: .Prompts.keychainSaveFailedTitle),
			body: error.localizedDescription + "\n\n" + String(localized: .Prompts.keychainQuitSaveFailedBody),
			defaultButton: String(localized: .Prompts.keychainRetrySave),
			alternateButton: String(localized: .Prompts.keychainQuitWithoutSaving),
			cancelButton: .default
		)
	}

	static func confirmTerminationRetry(_ error: any Error) async -> Bool {
		await Alerts.run(terminationFailureAlert(error), on: .mainWindow).response == .default
	}

	static func failureAlert(_ error: any Error, canRetry: Bool) -> AlertRequest {
		AlertRequest(
			title: String(localized: .Prompts.keychainSaveFailedTitle),
			body: error.localizedDescription,
			defaultButton: canRetry ? String(localized: .Prompts.keychainRetrySave) : PromptStrings.Action.confirmation,
			alternateButton: canRetry ? PromptStrings.Action.cancel : nil,
			otherButton: nil,
			cancelButton: canRetry ? .alternate : .default
		)
	}

	static func showFailure(_ error: any Error, retry: (() -> Void)? = nil) {
		Alerts.alertSheet(request: failureAlert(error, canRetry: retry != nil)) { outcome in
			if outcome.response == .default {
				retry?()
			}
		}
	}
}
