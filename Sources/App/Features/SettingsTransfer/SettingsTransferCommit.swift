// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** Applies an accepted transfer plan to the running application.

 The work either side of the QUIT barrier is different enough to be told
 apart: everything before it is teardown that can be abandoned, and everything
 after it is a reconciliation that has to run to the end. An import abandoned
 at the barrier has already disconnected servers, so it puts back the
 connections it took down before reporting why.

 Separate from `SettingsTransferSession` because the session is the state
 machine the sheet binds to, and this is the only part that names connections. */
@MainActor
struct SettingsTransferCommit {
	let stores: SettingsStores
	let chatSession: ChatSession
	let closeWait: Duration
	/// Whether this transfer drives the running application, and so has to stop
	/// when it is quitting and republish what it wrote.
	let usesApplication: Bool
	/// The live configuration, re-read wherever the plan has to still fit it.
	let liveSnapshot: @MainActor () throws -> SettingsArchive

	func apply(_ plan: SettingsTransferPlan) async throws {
		try checkApplicationIsRunning()
		chatSession.isImportingConfiguration = true
		defer { chatSession.isImportingConfiguration = false }
		let changed = sessionsAffected(by: plan)
		let interrupted = changed.filter { $0.isConnecting || $0.isConnected || $0.isReconnecting }
		do {
			try await closeConnections(of: changed)
			try checkStillApplicable(plan, changed: changed)
		} catch is CancellationError {
			throw CancellationError()
		} catch {
			resumeConnections(of: interrupted)
			throw error
		}
		reconcile(plan, changed: changed)
	}

	/// The sessions whose configuration, or whose channel list under Restore,
	/// the plan changes.
	private func sessionsAffected(by plan: SettingsTransferPlan) -> [ServerSession] {
		let desired = plan.result.sessions ?? []
		return chatSession.sessions.filter { session in
			let before = plan.before.sessions?.first { $0.uniqueIdentifier == session.uniqueIdentifier }
			let after = desired.first { $0.uniqueIdentifier == session.uniqueIdentifier }
			return before != after || (plan.mode == .restore &&
				session.conversationList.map(\.uniqueIdentifier) != after?.conversationList.map(\.uniqueIdentifier))
		}
	}

	/** The QUIT barrier.

	 Every affected connection's QUIT starts together, so Restore waits one
	 close deadline rather than one per server. The wait outlasts the
	 transport's own deadline, so a connection that has not reported back by
	 then is refused as its own error rather than mistaken for a stale preview. */
	private func closeConnections(of sessions: [ServerSession]) async throws {
		for session in sessions {
			session.cancelReconnect()
			session.cancelPendingSessionTasks()
		}
		let closing = sessions.filter { $0.isConnecting || $0.isConnected }
		guard closing.isEmpty == false else { return }
		let (disconnections, continuation) = AsyncStream<Void>.makeStream()
		defer { continuation.finish() }
		for session in closing {
			session.addDisconnectCallback { continuation.yield() }
			session.quit()
		}
		let expected = closing.count
		let closeWait = closeWait
		let allClosed = await withTaskGroup(of: Bool.self) { group in
			group.addTask {
				var remaining = expected
				for await _ in disconnections {
					remaining -= 1
					if remaining == 0 {
						return true
					}
				}
				return false
			}
			group.addTask {
				try? await Task.sleep(for: closeWait)
				return false
			}
			let first = await group.next() ?? false
			group.cancelAll()
			return first
		}
		try Task.checkCancellation()
		guard allClosed || closing.allSatisfy({ !$0.isConnecting && !$0.isConnected }) else {
			throw SettingsTransferError.connectionsDidNotClose
		}
	}

	/** Puts back the connections an abandoned import took down.

	 A session still closing reconnects once its disconnect lands; one that has
	 already closed reconnects now. Neither waits on the auto-reconnect
	 setting, because the user never asked for these servers to go offline. */
	private func resumeConnections(of sessions: [ServerSession]) {
		for session in sessions where session.isTerminating == false {
			if session.isConnecting || session.isConnected {
				session.addDisconnectCallback { [weak session] in
					session?.connect(.reconnect)
				}
			} else {
				session.connect(.reconnect)
			}
		}
	}

	/// Nothing may have moved between the barrier and the write.
	private func checkStillApplicable(_ plan: SettingsTransferPlan, changed: [ServerSession]) throws {
		try checkApplicationIsRunning()
		guard try liveSnapshot().hasSameConfiguration(as: plan.before),
		      changed.allSatisfy({ !$0.isTerminating && !$0.isConnecting && !$0.isConnected })
		else {
			throw SettingsTransferError.stalePreview
		}
	}

	private func checkApplicationIsRunning() throws {
		if usesApplication, AppServices.delegate.applicationIsTerminating {
			throw CancellationError()
		}
	}

	/// Everything after the barrier: publish the imported values, then bring
	/// the directory's sessions into line with the plan's.
	private func reconcile(_ plan: SettingsTransferPlan, changed: [ServerSession]) {
		let desired = plan.result.sessions ?? []
		for session in changed {
			session.cancelReconnect()
		}
		// Reconciliation rebuilds persisted channel lists using this consumer snapshot.
		// Publish it first, after validation/backup and the final stale-state check.
		plan.apply(to: stores, persistSessions: false)
		let settings = ChatSettings.current(stores: stores)
		chatSession.applySettings(settings)
		for session in chatSession.sessions
			where !desired.contains(where: { $0.uniqueIdentifier == session.uniqueIdentifier })
		{
			chatSession.destroySession(session, preservingLocalData: true)
		}
		for configuration in desired {
			let before = plan.before.sessions?.first { $0.uniqueIdentifier == configuration.uniqueIdentifier }
			guard before != configuration || changed
				.contains(where: { $0.uniqueIdentifier == configuration.uniqueIdentifier })
			else { continue }
			var configuration = configuration
			configuration.autoConnect = false
			if let session = chatSession.findSession(withId: configuration.uniqueIdentifier) {
				session.updateConfig(configuration, for: plan.mode == .restore ? .restore : .transfer)
			} else {
				_ = chatSession.createSession(with: configuration)
			}
		}
		for (index, configuration) in desired.enumerated() {
			if let oldIndex = chatSession.sessions
				.firstIndex(where: { $0.uniqueIdentifier == configuration.uniqueIdentifier }),
				oldIndex != index
			{
				chatSession.moveSession(from: oldIndex, to: index)
			}
		}
		// Include unchanged sessions too: a policy-only import can make their live
		// one-to-one conversations persistent.
		for session in chatSession.sessions {
			session.updateStoredConversationList()
		}
		stores.set(.array(chatSession.sessions.map { .dictionary($0.configurationDictionary()) }),
		           for: SettingsKeys.Sessions.serverSessions)
		if usesApplication {
			ObservableSettings.shared.invalidate()
			SettingsReload.perform(forKeys: plan.changedKeys)
		}
	}
}
