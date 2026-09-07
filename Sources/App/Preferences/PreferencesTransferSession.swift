/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Observation

struct PreferencesTransferPreview: Identifiable {
	let id = UUID()
	let filename: String
	let archive: PreferencesArchive
	let current: PreferencesArchive
	/** One plan per mode the file can be applied in.

	 A legacy dictionary has no restore plan, and that absence is the whole
	 story: it is what makes the Restore segment unavailable and what the
	 preview counts come from. Nothing else needs to ask the archive again. */
	private let plans: [PreferencesTransferMode: PreferencesTransferPlan]
	var mode = PreferencesTransferMode.merge

	init(
		filename: String,
		archive: PreferencesArchive,
		current: PreferencesArchive,
		plans: [PreferencesTransferMode: PreferencesTransferPlan]
	) {
		self.filename = filename
		self.archive = archive
		self.current = current
		self.plans = plans
	}

	/// The plan for the selected mode, or `nil` when the file cannot be applied
	/// that way.
	var plan: PreferencesTransferPlan? {
		plans[mode]
	}

	var supportsRestore: Bool {
		plans[.restore] != nil
	}
}

enum PreferencesTransferHost {
	case mainWindow, settings
}

enum PreferencesTransferClientSource {
	case application, stored
	case world(IRCWorld)
}

private enum PreferencesTransferInput {
	case portable(URL)
	case recovery(PreferencesRecoveryBackup)

	var url: URL {
		switch self {
		case let .portable(url): url
		case let .recovery(backup): backup.url
		}
	}
}

nonisolated struct PreferencesTransferResult: Sendable { // nonisolated: value
	let changedPreferences: Int
	let addedClients: Int
	let updatedClients: Int
	let removedClients: Int
	let ignoredKeys: Int
	let backup: PreferencesRecoveryBackup

	var summary: String {
		String(localized: .PreferencesTransfer.configurationImportedSettingsChanged(
			changedPreferences, addedClients, updatedClients, removedClients, ignoredKeys
		))
	}
}

/// What a completed transfer has to say for itself.
enum PreferencesTransferOutcome {
	case imported(PreferencesTransferResult)
	case exported

	var summary: String {
		switch self {
		case let .imported(result): result.summary
		case .exported: String(localized: .PreferencesTransfer.exportSucceeded)
		}
	}
}

/** Where the one transfer workflow has got to.

 Everything the presentation reads — whether a sheet is up, whether the window
 is busy, which alert to show — is derived from this one value, so there is no
 pair of flags that can disagree about what is happening. */
enum PreferencesTransferState {
	/// Nothing in flight and nothing waiting to be acknowledged.
	case idle
	/// Reading and planning a file, or encoding an export. The workflow has
	/// nothing of its own on screen yet.
	case preparing
	/// A prepared plan on screen, waiting for the user to accept or cancel it.
	case previewing(PreferencesTransferPreview)
	/// The accepted plan is being applied. The preview stays up, disabled.
	case committing(PreferencesTransferPreview)
	/// A transfer finished and its summary is waiting to be acknowledged.
	case finished(PreferencesTransferOutcome)
	/** Something stopped the workflow.

	 A commit that failed keeps its preview, so the message can be answered in
	 the sheet without losing the prepared plan. */
	case failed(message: String, preview: PreferencesTransferPreview?)
}

/// One workflow shared by menu commands and Settings, including recovery.
@MainActor
@Observable
final class PreferencesTransferSession {
	static let shared = PreferencesTransferSession()

	/** How long the QUIT barrier waits for the connections an import closes.

	 `IRCConnection.beginCloseDeadline` invalidates a socket that has not closed
	 five seconds after QUIT, so waiting longer than that is waiting on a
	 callback that is never coming. */
	private static let closeDeadline = Duration.seconds(5)

	private(set) var state = PreferencesTransferState.idle
	var host = PreferencesTransferHost.mainWindow
	private(set) var backups: [PreferencesRecoveryBackup] = []
	let recoveryStore: PreferencesRecoveryStore
	private let stores: PreferencesTransferStores
	private let clientSource: PreferencesTransferClientSource

	private var world: IRCWorld? {
		switch clientSource {
		case .application: AppController.shared.world
		case .stored: nil
		case let .world(world): world
		}
	}

	private var usesApplication: Bool {
		if case .application = clientSource {
			return true
		}
		return false
	}

	init(stores: PreferencesTransferStores = .live, recoveryDirectory: URL? = nil,
	     clientSource: PreferencesTransferClientSource = .application)
	{
		self.stores = stores
		self.clientSource = clientSource
		let support = recoveryDirectory ?? (PathInfo.applicationSupportURL ?? URL.applicationSupportDirectory)
			.appendingPathComponent("Configuration Backups", isDirectory: true)
		recoveryStore = PreferencesRecoveryStore(directory: support)
	}

	// MARK: - Derived state

	/// Work is in flight, so the window that owns it stays disabled.
	var isBusy: Bool {
		switch state {
		case .preparing, .committing: true
		case .idle, .previewing, .finished, .failed: false
		}
	}

	/// The prepared plan, while there is one to show.
	var preview: PreferencesTransferPreview? {
		switch state {
		case let .previewing(preview), let .committing(preview): preview
		case let .failed(_, preview): preview
		case .idle, .preparing, .finished: nil
		}
	}

	/// Which mode the preview will be applied in. Writing it is the only edit
	/// the sheet makes to a prepared plan.
	var previewMode: PreferencesTransferMode {
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

	var result: PreferencesTransferResult? {
		guard case let .finished(.imported(result)) = state else { return nil }
		return result
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
		case let .failed(_, preview): state = preview.map(PreferencesTransferState.previewing) ?? .idle
		case .idle, .preparing, .previewing, .committing: break
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

	func liveSnapshot() throws -> PreferencesArchive {
		let clients: [ClientConfig]
		if let world {
			clients = world.clientList.map { client in
				client.updateStoredConfiguration()
				var config = client.config
				config.channelList = IRCClientConfigurationPolicy.storedChannelConfigurations(
					from: client.channelList, rememberQueries: stores[Preferences.Appearance.rememberQueryStates]
				)
				return config
			}
		} else {
			let key = Preferences.Connection.clientList
			let value = stores.store(for: key).object(forKey: key.name).flatMap(PropertyListValue.init(propertyList:))
			clients = try value.map(PreferencesClientArchive.decode) ?? []
		}
		return stores.snapshot(clients: clients)
	}

	// MARK: - Preparing

	func prepareImport(from url: URL) async {
		await preparePreview(.portable(url))
	}

	func prepareRecovery(_ backup: PreferencesRecoveryBackup) async {
		await preparePreview(.recovery(backup))
	}

	private func preparePreview(_ input: PreferencesTransferInput) async {
		guard canStart else { report(PreferencesTransferError.busy); return }
		state = .preparing
		do {
			let archive: PreferencesArchive = switch input {
			case let .portable(url): try await PreferencesArchive.read(from: url)
			case let .recovery(backup): try await recoveryStore.read(backup)
			}
			let current = try liveSnapshot()
			let plans = try await Task.detached {
				var plans: [PreferencesTransferMode: PreferencesTransferPlan] = try [
					.merge: PreferencesTransferPlan(archive: archive, current: current, mode: .merge),
				]
				if archive.isComplete {
					plans[.restore] = try PreferencesTransferPlan(
						archive: archive, current: current, mode: .restore
					)
				}
				return plans
			}.value
			state = .previewing(PreferencesTransferPreview(
				filename: input.url.lastPathComponent, archive: archive, current: current, plans: plans
			))
		} catch {
			finishPreparing()
			report(error)
		}
	}

	func exportData(includeConnectCommands: Bool = false) async throws -> Data {
		guard canStart else { throw PreferencesTransferError.busy }
		state = .preparing
		defer { finishPreparing() }
		let snapshot = try liveSnapshot()
		return try await Task.detached {
			let data = try snapshot.encoded(includeConnectCommands: includeConnectCommands)
			let decoded = try PreferencesArchive.decode(data)
			_ = try PreferencesTransferPlan(archive: decoded, current: snapshot, mode: .restore)
			return data
		}.value
	}

	/// Leaves the preparing state without disturbing whatever replaced it.
	private func finishPreparing() {
		if case .preparing = state {
			state = .idle
		}
	}

	// MARK: - Committing

	func commitPreview() async {
		guard case let .previewing(preview) = state else { report(PreferencesTransferError.busy); return }
		state = .committing(preview)
		do {
			let current = try liveSnapshot()
			guard current.hasSameConfiguration(as: preview.current) else { throw PreferencesTransferError.stalePreview }
			let archive = preview.archive
			let mode = preview.mode
			let plan = try await Task.detached {
				try PreferencesTransferPlan(archive: archive, current: current, mode: mode)
			}.value
			let backup = try await recoveryStore.save(current)
			// Settings and clients may change while backup I/O suspends. Do not apply a stale preview.
			guard try liveSnapshot().hasSameConfiguration(as: current)
			else { throw PreferencesTransferError.stalePreview }
			try await commit(plan)
			state = .finished(.imported(PreferencesTransferResult(
				changedPreferences: plan.changedKeys.count, addedClients: plan.addedClients.count,
				updatedClients: plan.updatedClients.count, removedClients: plan.removedClients.count,
				ignoredKeys: archive.ignoredKeys.count, backup: backup
			)))
			await refreshBackups()
		} catch {
			state = .previewing(preview)
			report(error)
			await refreshBackups()
		}
	}

	/** Applies a plan to the live world.

	 The work either side of the QUIT barrier is different enough to be told
	 apart: everything before it is teardown that can be abandoned, and
	 everything after it is a reconciliation that has to run to the end. */
	private func commit(_ plan: PreferencesTransferPlan) async throws {
		guard let world else {
			guard case .stored = clientSource else { throw PreferencesTransferError.invalidDocument }
			stores.apply(plan)
			return
		}
		try checkApplicationIsRunning()
		world.isImportingConfiguration = true
		defer { world.isImportingConfiguration = false }
		let changed = clientsAffected(by: plan, in: world)
		try await closeConnections(of: changed)
		try checkStillApplicable(plan, changed: changed)
		apply(plan, to: world, changed: changed)
	}

	/// The clients whose configuration, or whose channel list under Restore,
	/// the plan changes.
	private func clientsAffected(by plan: PreferencesTransferPlan, in world: IRCWorld) -> [IRCClient] {
		let desired = plan.result.clients ?? []
		return world.clientList.filter { client in
			let before = plan.before.clients?.first { $0.uniqueIdentifier == client.uniqueIdentifier }
			let after = desired.first { $0.uniqueIdentifier == client.uniqueIdentifier }
			return before != after || (plan.mode == .restore &&
				client.channelList.map(\.uniqueIdentifier) != after?.channelList.map(\.uniqueIdentifier))
		}
	}

	/** The QUIT barrier.

	 Every affected connection's QUIT starts together, so Restore waits one
	 close deadline rather than one per server, and the wait is bounded by that
	 same deadline: a connection that never reports back is one the transport
	 has already given up on, and the check that follows decides whether the
	 import may still go ahead. */
	private func closeConnections(of clients: [IRCClient]) async throws {
		for client in clients {
			client.cancelReconnect()
			client.cancelPendingSessionTasks()
		}
		let closing = clients.filter { $0.isConnecting || $0.isConnected }
		guard closing.isEmpty == false else { return }
		let (disconnections, completion) = AsyncStream<Void>.makeStream()
		defer { completion.finish() }
		for client in closing {
			client.addDisconnectCallback { completion.yield() }
			client.quit()
		}
		let deadline = Task {
			try? await Task.sleep(for: Self.closeDeadline)
			completion.finish()
		}
		defer { deadline.cancel() }
		var remaining = closing.count
		for await _ in disconnections {
			try Task.checkCancellation()
			remaining -= 1
			if remaining <= 0 {
				break
			}
		}
		try Task.checkCancellation()
	}

	/// Nothing may have moved between the barrier and the write.
	private func checkStillApplicable(_ plan: PreferencesTransferPlan, changed: [IRCClient]) throws {
		try checkApplicationIsRunning()
		guard try liveSnapshot().hasSameConfiguration(as: plan.before),
		      changed.allSatisfy({ !$0.isTerminating && !$0.isConnecting && !$0.isConnected })
		else {
			throw PreferencesTransferError.stalePreview
		}
	}

	private func checkApplicationIsRunning() throws {
		if usesApplication, AppController.shared.applicationIsTerminating {
			throw CancellationError()
		}
	}

	/// Everything after the barrier: publish the imported values, then bring
	/// the world's clients into line with the plan's.
	private func apply(_ plan: PreferencesTransferPlan, to world: IRCWorld, changed: [IRCClient]) {
		let desired = plan.result.clients ?? []
		for client in changed {
			client.cancelReconnect()
		}
		// Reconciliation rebuilds persisted channel lists using this consumer snapshot.
		// Publish it first, after validation/backup and the final stale-state check.
		stores.apply(plan, persistClients: false)
		let preferences = ClientPreferences.current(stores: stores)
		world.applyPreferences(preferences)
		if usesApplication {
			ClientEnvironment.shared.preferences = preferences
		}
		for client in world.clientList
			where !desired.contains(where: { $0.uniqueIdentifier == client.uniqueIdentifier })
		{
			world.destroyClient(client, preservingLocalData: true)
		}
		for configuration in desired {
			let before = plan.before.clients?.first { $0.uniqueIdentifier == configuration.uniqueIdentifier }
			guard before != configuration || changed
				.contains(where: { $0.uniqueIdentifier == configuration.uniqueIdentifier })
			else { continue }
			var configuration = configuration
			configuration.autoConnect = false
			if let client = world.findClient(withId: configuration.uniqueIdentifier) {
				client.updateConfig(configuration, for: plan.mode == .restore ? .restore : .transfer)
			} else {
				_ = world.createClient(with: configuration)
			}
		}
		for (index, configuration) in desired.enumerated() {
			if let oldIndex = world.clientList
				.firstIndex(where: { $0.uniqueIdentifier == configuration.uniqueIdentifier }),
				oldIndex != index
			{
				world.moveClient(from: oldIndex, to: index)
			}
		}
		// Include unchanged clients too: a policy-only import can make their live queries persistent.
		for client in world.clientList {
			client.updateStoredChannelList()
		}
		stores.set(.array(world.clientList.map { .dictionary($0.configurationDictionary()) }),
		           for: Preferences.Connection.clientList)
		if usesApplication {
			ObservablePreferences.shared.invalidate()
			TextualPreferences.performReloadAction(forKeys: plan.changedKeys)
		}
	}

	// MARK: - Reporting

	func report(_ error: any Error) {
		// A closed file panel is the user saying "nothing", not a failure.
		guard (error as? CocoaError)?.code != .userCancelled else { return }
		state = .failed(message: error.localizedDescription, preview: preview)
	}

	func completeExport(_ result: Result<URL, any Error>) {
		switch result {
		case .success: state = .finished(.exported)
		case let .failure(error): report(error)
		}
	}
}
