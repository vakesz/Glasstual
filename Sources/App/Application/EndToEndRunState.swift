// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/** What an end-to-end run leaves behind, and its removal as the run's last
 launch quits.

 The harness cannot reach into the application's sandbox to clean up after
 it, so the application removes its own run state: the review defaults suite,
 the review directories and the keychain items stored under the run's prefix.
 A launch the harness relaunches keeps all three for the next one. */
enum EndToEndRunState {
	private static let logger = Logger(subsystem: LogSubsystem.application, category: "EndToEndRunState")

	/// Called once the session has saved, as the application is about to exit.
	static func removeIfRequested() {
		#if DEBUG
			guard ApplicationForeground.mode.removesRunStateOnQuit else { return }

			let suite = ProcessInfo.processInfo.environment["GLASSTUAL_UI_REVIEW_SUITE"] ?? ""
			/* Never the application's own domains: the run's suite is the only
			 settings this may remove. */
			if suite.isEmpty == false, suite != ApplicationGroup.identifier,
			   suite != Bundle.main.bundleIdentifier
			{
				/* Through the run's own handle, which caches the domain: a removal
				 through another handle is undone when this one writes back. */
				GlasstualUserDefaults.container.removePersistentDomain(forName: suite)
				CFPreferencesAppSynchronize(suite as CFString)
			}
			if ApplicationPaths.removeUIReviewDirectories() == false {
				logger.error("Could not remove the end-to-end run's review directories")
			}
			if KeychainItem.deleteIsolatedItems() == false {
				logger.error("Could not remove the end-to-end run's keychain items")
			}
		#endif
	}
}
