// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation
import SwiftUI

/** What one transcript has to tell the reader about history it could not load.

 One object per view, observed by ``TranscriptHistoryRecoveryView``: the
 controller records what failed, the banner decides what that reads as. Failures
 that belong to the database rather than to any one conversation are
 ``ScrollbackStorageRecovery``'s, which the banner composes with this. */
@MainActor
@Observable
final class TranscriptHistoryRecovery {
	var initialFailure: ScrollbackFetchFailure?
	var olderFailure: ScrollbackFetchFailure?
	var serverFailed = false
	var serverFailureReason: String?
	/// Mirrors `TranscriptController.serverHistoryRetryIsAvailable`, which reads
	/// state SwiftUI does not observe; the controller refreshes it whenever
	/// that state moves.
	var serverRetryIsAvailable = false
	var isRetrying = false

	/// What this view's own failure reads as, or nothing where its history
	/// loaded.
	var localMessage: String? {
		guard let failure = initialFailure ?? olderFailure else { return nil }
		if case let .read(reason) = failure {
			return reason
		}
		return PromptStrings.Logging.scrollbackFailureBody
	}
}

/** The banner a transcript draws over history it could not load.

 It composes the two halves that can fail: the view's own history
 (``TranscriptHistoryRecovery``, which only a controller has) and the database
 the whole process shares (``ScrollbackStorageRecovery``). A view's own failure
 is the more specific answer, so it is the one the banner leads with. */
struct TranscriptHistoryRecoveryView: View {
	let controller: TranscriptController?

	var body: some View {
		let history = controller?.historyRecovery
		let storage = controller?.storageRecovery ?? Scrollback.shared.recovery
		let message = history?.localMessage ?? storage.localMessage
		let isRetrying = history?.isRetrying ?? storage.isRetrying
		let serverFailed = history?.serverFailed ?? false
		if message != nil || serverFailed || isRetrying {
			HStack(alignment: .top) {
				/* The glyph is the only thing that says this is a warning, so it
				 is tinted like one and named for a reader who cannot see it. */
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundStyle(.orange)
					.accessibilityLabel(String(localized: .Transcript.warningAccessibility))
				VStack(alignment: .leading, spacing: 4) {
					Text(serverFailed && message == nil ?
						String(localized: .Transcript.serverHistoryCouldNotBeLoaded) :
						String(localized: .Transcript.localHistoryNeedsAttention))
						.font(.headline)
					if let detail = message ?? history?.serverFailureReason {
						Text(detail).font(.caption).textSelection(.enabled)
					}
				}
				Spacer()
				if isRetrying {
					ProgressView().controlSize(.small)
				}
				if message != nil {
					Button(String(localized: .Transcript.retry)) {
						if let controller {
							controller.retryHistory()
						} else {
							storage.isRetrying = true
							Task {
								_ = await Scrollback.shared.retryLoading()
								storage.isRetrying = false
							}
						}
					}
					.disabled(isRetrying)
					.accessibilityIdentifier("history-retry")
				}
				if serverFailed {
					Button(String(localized: .Transcript.retryServer)) { controller?.retryServerHistory() }
						.disabled(history?.serverRetryIsAvailable != true)
						.accessibilityIdentifier("server-history-retry")
				}
			}
			.padding(10)
			.background(.bar)
			.accessibilityElement(children: .contain)
			.accessibilityIdentifier("history-recovery")
		}
	}
}
