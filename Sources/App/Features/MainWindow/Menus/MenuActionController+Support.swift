// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import os

private let menuSupportLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "MenuSupport"
)

// MARK: - Logs, credits and the support channels

extension MenuActionController {
	@objc func openLogLocation(_: Any?) {
		openLog(at: ApplicationPaths.transcriptFolderURL)
	}

	@objc func openChannelLogs(_: Any?) {
		openLog(at: selectedChannel?.logFilePath)
	}

	@objc func openAcknowledgements(_: Any?) {
		guard let url = Bundle.main.url(
			forResource: "Acknowledgements",
			withExtension: "pdf",
			subdirectory: "Documentation"
		) else {
			menuSupportLogger.error("Acknowledgements.pdf is missing from the application bundle")
			return
		}
		NSWorkspace.shared.open(url)
	}

	@objc func connectToGlasstualHelpChannel(_: Any?) {
		ServerConnectionController.connect(to: .help)
	}

	@objc func connectToGlasstualTestingChannel(_: Any?) {
		ServerConnectionController.connect(to: .testing)
	}

	private func openLog(at url: URL?) {
		guard let url else { return }
		if FileManager.default.fileExists(atPath: url.path) {
			NSWorkspace.shared.open(url)
			return
		}
		Alerts.alert(
			withMessage: PromptStrings.Logging.emptyAlertBody,
			title: PromptStrings.Logging.noLogsTitle,
			defaultButton: PromptStrings.Action.confirmation
		)
	}
}
