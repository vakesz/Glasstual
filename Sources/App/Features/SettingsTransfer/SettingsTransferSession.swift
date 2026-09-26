// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Observation
import os

private let transferLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "SettingsTransferSession"
)

struct SettingsTransferPreview: Identifiable {
	let id = UUID()
	let filename: String
	let archive: SettingsArchive
	let current: SettingsArchive
	/** One plan per mode the file can be applied in.

	 A mode with no plan is one this file cannot be applied in, which is what
	 makes its segment unavailable; the preview counts come from the plan the
	 selected mode has. Nothing else needs to ask the archive again. */
	private let plans: [SettingsTransferMode: SettingsTransferPlan]
	var mode = SettingsTransferMode.merge

	init(
		filename: String,
		archive: SettingsArchive,
		current: SettingsArchive,
		plans: [SettingsTransferMode: SettingsTransferPlan]
	) {
		self.filename = filename
		self.archive = archive
		self.current = current
		self.plans = plans
	}

	/// The plan for the selected mode, or `nil` when the file cannot be applied
	/// that way.
	var plan: SettingsTransferPlan? {
		plans[mode]
	}
}

enum SettingsTransferHost {
	case mainWindow, settings
}

enum SettingsTransferSessionSource {
	case application, stored
	case chatSession(ChatSession)
}

private enum SettingsTransferInput {
	case portable(URL)
	case recovery(SettingsRecoveryBackup)

	var url: URL {
		switch self {
		case let .portable(url): url
		case let .recovery(backup): backup.url
		}
	}
}

nonisolated struct SettingsTransferResult: Sendable {
	let changedSettings: Int
	let addedSessions: Int
	let updatedSessions: Int
	let removedSessions: Int
	let ignoredKeys: Int
	let backup: SettingsRecoveryBackup

	var summary: String {
		String(localized: .SettingsTransfer.configurationImportedSettingsChanged(
			changedSettings, addedSessions, updatedSessions, removedSessions, ignoredKeys
		))
	}
}

/// One message the transfer workflow is waiting to have acknowledged.
struct SettingsTransferMessage: Equatable {
	let title: String
	let body: String
}

/// What a completed transfer has to say for itself.
enum SettingsTransferOutcome {
	case imported(SettingsTransferResult)
	case exported

	var summary: String {
		switch self {
		case let .imported(result): result.summary
		case .exported: String(localized: .SettingsTransfer.exportSucceeded)
		}
	}
}

/** Where the one transfer workflow has got to.

 Everything the presentation reads — whether a sheet is up, whether the window
 is busy, which alert to show — is derived from this one value, so there is no
 pair of flags that can disagree about what is happening. */
enum SettingsTransferState {
	/// Nothing in flight and nothing waiting to be acknowledged.
	case idle
	/// Reading and planning a file, or encoding an export. The workflow has
	/// nothing of its own on screen yet.
	case preparing
	/// The encoded export is waiting for its Save panel to finish.
	case exporting
	/// A prepared plan on screen, waiting for the user to accept or cancel it.
	case previewing(SettingsTransferPreview)
	/// The accepted plan is being applied. The preview stays up, disabled.
	case committing(SettingsTransferPreview)
	/// A transfer finished and its summary is waiting to be acknowledged.
	case finished(SettingsTransferOutcome)
	/** Something stopped the workflow.

	 A commit that failed keeps its preview, so the message can be answered in
	 the sheet without losing the prepared plan. */
	case failed(message: String, preview: SettingsTransferPreview?)
}

/// One workflow shared by menu commands and Settings, including recovery.
@MainActor
@Observable
final class SettingsTransferSession {
	/** How long the QUIT barrier waits for the connections an import closes.

	 The transport gives a socket five seconds after QUIT before it invalidates
	 it and reports the disconnect itself. Waiting exactly that long raced that
	 report, so the barrier waits past it: a connection still open after this
	 is one the transport never let go of. */
	static let closeWait = Duration.seconds(8)

	private(set) var state = SettingsTransferState.idle
	var host = SettingsTransferHost.mainWindow
	private(set) var backups: [SettingsRecoveryBackup] = []
	let recoveryStore: SettingsRecoveryStore
	private let stores: SettingsStores
	private let sessionSource: SettingsTransferSessionSource

	private var chatSession: ChatSession? {
		switch sessionSource {
		case .application: AppServices.chatSession
		case .stored: nil
		case let .chatSession(chatSession): chatSession
		}
	}

	private var usesApplication: Bool {
		if case .application = sessionSource {
			return true
		}
		return false
	}

	private let closeWait: Duration

	init(stores: SettingsStores = .live, recoveryDirectory: URL? = nil,
	     sessionSource: SettingsTransferSessionSource = .application, closeWait: Duration = closeWait)
	{
		self.stores = stores
		self.sessionSource = sessionSource
		self.closeWait = closeWait
		recoveryStore = SettingsRecoveryStore(directory: recoveryDirectory ?? SettingsRecoveryStore.defaultDirectory)
	}

	// MARK: - Derived state

	/// Work is in flight, so the window that owns it stays disabled.
	var isBusy: Bool {
		switch state {
		case .preparing, .exporting, .committing: true
		case .idle, .previewing, .finished, .failed: false
		}
	}

	/// The prepared plan, while there is one to show.
	var preview: SettingsTransferPreview? {
		switch state {
		case let .previewing(preview), let .committing(preview): preview
		case let .failed(_, preview): preview
		case .idle, .preparing, .exporting, .finished: nil
		}
	}

	/// Which mode the preview will be applied in. Writing it is the only edit
	/// the sheet makes to a prepared plan.
	var previewMode: SettingsTransferMode {
		get { preview?.mode ?? .merge }
		set {
			guard case var .previewing(preview) = state else { return }
			preview.mode = newValue
			state = .previewing(preview)
		}
	}

	var errorMessage: String? {
		if case let .failed(message, _) = state {
			message
		} else {
			nil
		}
	}

	var completionMessage: String? {
		if case let .finished(outcome) = state {
			outcome.summary
		} else {
			nil
		}
	}

	var result: SettingsTransferResult? {
		guard case let .finished(.imported(result)) = state else { return nil }
		return result
	}

	/** The one message on offer, whichever way the workflow ended.

	 Derived from the state rather than assembled per alert, so two alerts can
	 never both think they are the current one. */
	var pendingMessage: SettingsTransferMessage? {
		switch state {
		case let .failed(message, _):
			SettingsTransferMessage(
				title: String(localized: .SettingsTransfer.configurationTransferStopped),
				body: message
			)
		case let .finished(outcome):
			SettingsTransferMessage(
				title: String(localized: .SettingsTransfer.configurationTransferComplete),
				body: outcome.summary
			)
		case .idle, .preparing, .exporting, .previewing, .committing:
			nil
		}
	}

	/// Whether a new import or export may begin. A prepared preview is still
	/// waiting on the user, so it holds the workflow just as a busy one does.
	var canStart: Bool {
		isBusy == false && preview == nil
	}

	/// Dismisses whichever message the workflow last produced, keeping a
	/// preview that survived a failed commit.
	func acknowledge() {
		switch state {
		case .finished: state = .idle
		case let .failed(_, preview): state = preview.map(SettingsTransferState.previewing) ?? .idle
		case .idle, .preparing, .exporting, .previewing, .committing: break
		}
	}

	/// Abandons the prepared plan without applying any of it.
	func cancelPreview() {
		guard isBusy == false else { return }
		state = .idle
	}

	// MARK: - Reading the live configuration

	func refreshBackups() async {
		do {
			backups = try await recoveryStore.backups()
		} catch {
			report(error)
		}
	}

	func liveSnapshot() throws -> SettingsArchive {
		let sessions: [ServerConfig]
		if let chatSession {
			sessions = chatSession.sessions.map { session in
				session.updateStoredConfiguration()
				var config = session.config
				config.conversationList = ServerConfigPolicy.storedConversationConfigurations(
					from: session.conversationList, rememberDirectConversations: stores[SettingsKeys.Appearance.rememberDirectConversations]
				)
				return config
			}
		} else {
			let key = SettingsKeys.Sessions.serverSessions
			let value = stores.store(for: key).object(forKey: key.name).flatMap(PropertyListValue.init(propertyList:))
			sessions = try value.map(SettingsSessionArchive.decode) ?? []
		}
		return SettingsArchive.snapshot(from: stores, sessions: sessions)
	}

	// MARK: - Preparing

	func prepareImport(from url: URL) async {
		await preparePreview(.portable(url))
	}

	func prepareRecovery(_ backup: SettingsRecoveryBackup) async {
		await preparePreview(.recovery(backup))
	}

	private func preparePreview(_ input: SettingsTransferInput) async {
		guard canStart else { return }
		state = .preparing
		do {
			let archive: SettingsArchive = switch input {
			case let .portable(url): try await SettingsArchive.read(from: url)
			case let .recovery(backup): try await recoveryStore.read(backup)
			}
			let current = try liveSnapshot()
			let plans = try await SettingsTransferPreparation.plans(archive: archive, current: current)
			try Task.checkCancellation()
			state = .previewing(SettingsTransferPreview(
				filename: input.url.lastPathComponent, archive: archive, current: current, plans: plans
			))
		} catch is CancellationError {
			finishPreparing()
		} catch {
			finishPreparing()
			report(error)
		}
	}

	/// Keeps the workflow reserved until the Save panel calls `completeExport`.
	func exportData(includeConnectCommands: Bool = false) async throws -> Data {
		guard canStart else { throw SettingsTransferError.busy }
		state = .preparing
		defer { finishPreparing() }
		let snapshot = try liveSnapshot()
		let data = try await SettingsTransferPreparation.export(snapshot, includeConnectCommands: includeConnectCommands)
		try Task.checkCancellation()
		state = .exporting
		return data
	}

	/// Leaves the preparing state without disturbing whatever replaced it.
	private func finishPreparing() {
		if case .preparing = state {
			state = .idle
		}
	}

	// MARK: - Committing

	func commitPreview() async {
		guard case let .previewing(preview) = state else { return }
		state = .committing(preview)
		do {
			let current = try liveSnapshot()
			guard current.hasSameConfiguration(as: preview.current) else { throw SettingsTransferError.stalePreview }
			let archive = preview.archive
			let mode = preview.mode
			let plan = try await SettingsTransferPreparation.plan(archive: archive, current: current, mode: mode)
			let backup = try await recoveryStore.save(current)
			// Settings and sessions may change while backup I/O suspends. Do not apply a stale preview.
			guard try liveSnapshot().hasSameConfiguration(as: current)
			else { throw SettingsTransferError.stalePreview }
			try Task.checkCancellation()
			try await commit(plan)
			state = .finished(.imported(SettingsTransferResult(
				changedSettings: plan.changedKeys.count, addedSessions: plan.addedSessions.count,
				updatedSessions: plan.updatedSessions.count, removedSessions: plan.removedSessions.count,
				ignoredKeys: archive.ignoredKeys.count, backup: backup
			)))
			await refreshBackups()
		} catch {
			state = .previewing(preview)
			report(error)
			await refreshBackups()
		}
	}

	/// Applies an accepted plan: to the stored configuration when there is no
	/// running directory, and otherwise through `SettingsTransferCommit`.
	private func commit(_ plan: SettingsTransferPlan) async throws {
		guard let chatSession else {
			guard case .stored = sessionSource else { throw SettingsTransferError.invalidDocument }
			plan.apply(to: stores)
			return
		}
		try await SettingsTransferCommit(
			stores: stores,
			chatSession: chatSession,
			closeWait: closeWait,
			usesApplication: usesApplication,
			liveSnapshot: { try self.liveSnapshot() }
		).apply(plan)
	}

	// MARK: - Reporting

	func report(_ error: any Error) {
		// A closed file panel is the user saying "nothing", not a failure.
		guard (error as? CocoaError)?.code != .userCancelled else { return }
		if case SettingsTransferError.busy = error {
			return
		}
		// A background read or another panel must not replace the active operation.
		guard !isBusy else {
			transferLogger.error("Configuration error during an active transfer: \(error.localizedDescription, privacy: .public)")
			return
		}
		/* The alert says a value was refused; which one is a question for
		 whoever is looking at the file, so the name goes to the log rather
		 than into a sentence full of defaults spelling. */
		if case let SettingsTransferError.invalidValue(name) = error {
			transferLogger.error("Refused the stored value for \(name, privacy: .public).")
		}
		state = .failed(message: error.localizedDescription, preview: preview)
	}

	func completeExport(_ result: Result<URL, any Error>) {
		guard case .exporting = state else { return }
		state = .idle
		switch result {
		case .success: state = .finished(.exported)
		case let .failure(error): report(error)
		}
	}
}

/// CPU work leaves the calling actor without creating an independent task.
private nonisolated enum SettingsTransferPreparation {
	@concurrent
	static func plans(archive: SettingsArchive,
	                  current: SettingsArchive) async throws -> [SettingsTransferMode: SettingsTransferPlan]
	{
		try Task.checkCancellation()
		let plans: [SettingsTransferMode: SettingsTransferPlan] = try [
			.merge: SettingsTransferPlan(archive: archive, current: current, mode: .merge),
			.restore: SettingsTransferPlan(archive: archive, current: current, mode: .restore),
		]
		try Task.checkCancellation()
		return plans
	}

	@concurrent
	static func plan(archive: SettingsArchive, current: SettingsArchive,
	                 mode: SettingsTransferMode) async throws -> SettingsTransferPlan
	{
		try Task.checkCancellation()
		let plan = try SettingsTransferPlan(archive: archive, current: current, mode: mode)
		try Task.checkCancellation()
		return plan
	}

	@concurrent
	static func export(_ snapshot: SettingsArchive, includeConnectCommands: Bool) async throws -> Data {
		try Task.checkCancellation()
		let data = try snapshot.encoded(includeConnectCommands: includeConnectCommands)
		let decoded = try SettingsArchive.decode(data)
		_ = try SettingsTransferPlan(archive: decoded, current: snapshot, mode: .restore)
		try Task.checkCancellation()
		return data
	}
}
