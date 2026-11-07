// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** What the window says while the saved history is being upgraded for search.

 The upgrade runs once, the first time an older history store is opened, and
 history is not read or written until it finishes. The banner is the reason the
 transcript is empty for that while, with the progress of the copy. */
struct ScrollbackMigrationBanner: View {
	let recovery: ScrollbackStorageRecovery

	var body: some View {
		if let fraction = recovery.migrationFraction {
			VStack(alignment: .leading, spacing: UISpacing.tight) {
				Text(.Transcript.historyUpgradeProgress)
					.font(.headline)
				ProgressView(value: fraction)
					.accessibilityLabel(Text(.Transcript.historyUpgradeProgress))
			}
			.padding(UISpacing.regular)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(.bar)
			.accessibilityElement(children: .contain)
			.accessibilityIdentifier("history-upgrade-progress")
		}
	}
}
