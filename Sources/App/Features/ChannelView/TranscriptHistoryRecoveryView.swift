/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Observation
import SwiftUI

/** What a transcript has to tell the reader about history it could not load.

 One object per view, observed by ``TranscriptHistoryRecoveryView``: the
 controller records what failed, the banner decides what that reads as. The
 shared storage facade keeps one of these too, for failures that belong to the
 database rather than to any one conversation. */
@MainActor
@Observable
final class TranscriptHistoryRecoveryState {
	var initialFailure: HistoricLogFetchFailure?
	var olderFailure: HistoricLogFetchFailure?
	var storageFailure: String?
	var deletionFailures: [String: String] = [:]
	var serverFailed = false
	var serverFailureReason: String?
	/// Mirrors `LogController.serverHistoryRetryIsAvailable`, which reads
	/// state SwiftUI does not observe; the controller refreshes it whenever
	/// that state moves.
	var serverRetryIsAvailable = false
	var isRetrying = false

	var localMessage: String? {
		if !deletionFailures.isEmpty {
			let details = Set(deletionFailures.values).sorted()
			return ([String(localized: .TranscriptHistory.deletionNotRepeated)] + details +
				[storageFailure].compactMap(\.self)).joined(separator: "\n")
		}
		if let storageFailure {
			return storageFailure
		}
		guard let failure = initialFailure ?? olderFailure else { return nil }
		if case let .read(reason) = failure {
			return reason
		}
		return PromptStrings.Logging.scrollbackFailureBody
	}
}

struct TranscriptHistoryRecoveryView: View {
	let controller: LogController?

	var body: some View {
		let state = controller?.historyRecovery ?? LogControllerHistoricLogFile.sharedInstance.recovery
		let message = state.localMessage ?? controller?.historyStorageRecovery.localMessage
		if message != nil || state.serverFailed || state.isRetrying {
			HStack(alignment: .top) {
				Image(systemName: "exclamationmark.triangle")
				VStack(alignment: .leading, spacing: 4) {
					Text(state
						.serverFailed && message == nil ?
						String(localized: .TranscriptHistory.serverHistoryCouldNotBeLoaded) :
						String(localized: .TranscriptHistory.localHistoryNeedsAttention))
						.font(.headline)
					if let detail = message ?? state.serverFailureReason {
						Text(detail).font(.caption).textSelection(.enabled)
					}
				}
				Spacer()
				if state.isRetrying {
					ProgressView().controlSize(.small)
				}
				if message != nil {
					Button(String(localized: .TranscriptHistory.retry)) {
						if let controller {
							controller.retryHistory()
						} else {
							state.isRetrying = true
							Task {
								_ = await LogControllerHistoricLogFile.sharedInstance.retryLoading()
								state.isRetrying = false
							}
						}
					}
					.disabled(state.isRetrying)
					.accessibilityIdentifier("history-retry")
				}
				if state.serverFailed {
					Button(String(localized: .TranscriptHistory.retryServer)) { controller?.retryServerHistory() }
						.disabled(!state.serverRetryIsAvailable)
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
