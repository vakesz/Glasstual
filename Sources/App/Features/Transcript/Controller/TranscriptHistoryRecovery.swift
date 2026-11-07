// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation
import SwiftUI

/** The state of one transcript's local history loads and recovery banner.

 One object per view, observed by ``TranscriptHistoryRecoveryView``: the
 controller records load phases and failures, and the banner presents them. Failures
 that belong to the database rather than to any one conversation are
 ``ScrollbackStorageRecovery``'s, which the banner composes with this. */
@MainActor
@Observable
final class TranscriptHistoryRecovery {
	private enum LoadPhase {
		case unloaded
		case loading(wasLoaded: Bool)
		case loaded
	}

	private enum OlderPagePhase {
		case idle
		case loading
	}

	private var loadPhase = LoadPhase.unloaded
	private var olderPagePhase = OlderPagePhase.idle
	private(set) var hasEverLoaded = false

	var isLoaded: Bool {
		switch loadPhase {
		case .loaded, .loading(wasLoaded: true): true
		case .unloaded, .loading(wasLoaded: false): false
		}
	}

	var isReloading: Bool {
		if case .loading = loadPhase {
			return true
		}

		return false
	}

	var isLoadingOlderPage: Bool {
		if case .loading = olderPagePhase {
			return true
		}

		return false
	}

	func beginReload() {
		loadPhase = .loading(wasLoaded: isLoaded)
	}

	func finishReload(succeeded: Bool) {
		loadPhase = succeeded ? .loaded : .unloaded
		hasEverLoaded = hasEverLoaded || succeeded
	}

	func cancelReload() {
		guard case let .loading(wasLoaded) = loadPhase else { return }
		loadPhase = wasLoaded ? .loaded : .unloaded
	}

	func clearLoadedHistory() {
		loadPhase = .unloaded
	}

	/** Whether the transcript shows a window of stored history rather than the
	 live end of the conversation. While it does, new lines are stored and not
	 drawn, and the banner offers the way back. */
	private(set) var isDetachedFromLive = false

	/// A window replaces whatever the view held, so a load that has not run yet
	/// has nothing left to add and must not run later on top of it. Coming back
	/// reads stored history as any later reload does.
	func beginDetached() {
		isDetachedFromLive = true
		hasEverLoaded = true
		if case .unloaded = loadPhase {
			loadPhase = .loaded
		}
	}

	func endDetached() {
		isDetachedFromLive = false
	}

	func beginOlderPage() {
		olderPagePhase = .loading
	}

	func endOlderPage() {
		olderPagePhase = .idle
	}

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
		VStack(spacing: 0) {
			if history?.isDetachedFromLive == true {
				TranscriptDetachedBanner { controller?.returnToLive() }
			}
			failureBanner(
				controller: controller, history: history, storage: storage,
				message: message, isRetrying: isRetrying, serverFailed: serverFailed
			)
		}
	}

	@ViewBuilder
	private func failureBanner(
		controller: TranscriptController?,
		history: TranscriptHistoryRecovery?,
		storage: ScrollbackStorageRecovery,
		message: String?,
		isRetrying: Bool,
		serverFailed: Bool
	) -> some View {
		if message != nil || serverFailed || isRetrying {
			HStack(alignment: .top) {
				/* The glyph is the only thing that says this is a warning, so it
				 is tinted like one and named for a reader who cannot see it. */
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundStyle(.orange)
					.accessibilityLabel(String(localized: .Transcript.warningAccessibility))
				VStack(alignment: .leading, spacing: UISpacing.tight) {
					Text(serverFailed && message == nil ?
						String(localized: .Transcript.serverHistoryCouldNotBeLoaded) :
						String(localized: .Transcript.localHistoryNeedsAttention))
						.font(.headline)
					if let detail = message ?? history?.serverFailureReason {
						Text(verbatim: detail).font(.caption).textSelection(.enabled)
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
			.padding(UISpacing.regular)
			.background(.bar)
			.accessibilityElement(children: .contain)
			.accessibilityIdentifier("history-recovery")
		}
	}
}

/** The banner over a window of stored history: this is not the end of the
 conversation, and one control returns to it. New lines are stored while it is
 up, so nothing is missed. */
struct TranscriptDetachedBanner: View {
	let returnToLive: () -> Void

	var body: some View {
		HStack {
			Image(systemName: "clock.arrow.circlepath")
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)
			Text(.Transcript.viewingHistory)
				.font(.headline)
			Spacer()
			Button(String(localized: .Transcript.returnToLive), action: returnToLive)
				.accessibilityIdentifier("history-return-to-live")
		}
		.padding(UISpacing.regular)
		.background(.bar)
		.accessibilityElement(children: .contain)
		.accessibilityIdentifier("history-window-banner")
	}
}
