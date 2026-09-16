/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation

/// Accepts edits on the main actor in their commit order; Security calls run
/// on the writer actor. A failed batch does not prevent a later retry.
final class KeychainPersistence {
	typealias Edits = [KeychainItem: PendingKeychainSecret]
	typealias FailureReporter = @MainActor (any Error, @escaping @MainActor () -> Void) -> Void
	private let reportFailure: FailureReporter
	private let write: @Sendable (Edits) async throws -> Void
	private var tail: Task<Void, Error>?
	private var latestRevisions: [KeychainItem: UUID] = [:]
	private var latestEdits: Edits = [:]
	private var failures: [KeychainItem: any Error] = [:]
	private var submission = UUID()
	private var isFinishingTermination = false
	private var observers: [UUID: Task<Void, Never>] = [:]
	private var settingsSaves: [UUID: Task<Void, Never>] = [:]
	private var settingsSaveFailure = UUID()

	init(
		write: @escaping @Sendable (Edits) async throws -> Void = { try await KeychainWriter.shared.apply($0) },
		reportFailure: @escaping FailureReporter = { _, _ in }
	) {
		self.reportFailure = reportFailure
		self.write = write
	}

	var hasPendingSettingsSaves: Bool {
		!settingsSaves.isEmpty
	}

	/// Owns an accepted editor save through preparation, credential writes and
	/// the configuration commit. Quit waits before closing any editor or client.
	func submitSettingsSave(_ operation: @escaping @MainActor () async -> Bool) -> Task<Void, Never> {
		let identifier = UUID()
		let task = Task {
			let succeeded = await operation()
			if !succeeded {
				settingsSaveFailure = UUID()
			}
			settingsSaves[identifier] = nil
		}
		settingsSaves[identifier] = task
		return task
	}

	/// Includes saves accepted while an earlier save is still suspended. A
	/// failure leaves the editor open and prevents irreversible quit teardown.
	func waitForSettingsSaves() -> Task<Bool, Never> {
		let previousFailure = settingsSaveFailure
		return Task {
			while !settingsSaves.isEmpty {
				for task in Array(settingsSaves.values) {
					await task.value
				}
			}
			return previousFailure == settingsSaveFailure
		}
	}

	func enqueue(
		_ edits: Edits,
		revision: UUID = UUID(),
		retainsFailureForTermination: Bool = true
	) -> Task<Void, Error> {
		submission = UUID()
		for (item, edit) in edits {
			latestRevisions[item] = revision
			latestEdits[item] = edit
			failures[item] = nil
		}
		let previous = tail
		let write = write
		let task = Task {
			_ = await previous?.result
			do {
				try Task.checkCancellation()
				if !edits.isEmpty {
					try await write(edits)
				}
			} catch {
				for item in edits.keys where latestRevisions[item] == revision {
					if retainsFailureForTermination {
						failures[item] = error
					} else {
						latestRevisions[item] = nil
						latestEdits[item] = nil
						failures[item] = nil
					}
				}
				throw error
			}
			for item in edits.keys where latestRevisions[item] == revision {
				latestRevisions[item] = nil
				latestEdits[item] = nil
				failures[item] = nil
			}
		}
		tail = task
		return task
	}

	/// Model commits keep their edits until this callback acknowledges success.
	/// The service owns persistence even if the model is removed in the meantime.
	func persist(_ edits: Edits, onSuccess: @escaping (Edits) -> Void = { _ in }) {
		guard !edits.isEmpty else { return }
		let revision = UUID()
		let task = enqueue(edits, revision: revision)
		let identifier = UUID()
		observers[identifier] = Task { [weak self] in
			do {
				try await task.value
				onSuccess(edits)
			} catch {
				if self?.isFinishingTermination == false {
					self?.reportFailure(error) { [weak self] in
						guard let self, !isFinishingTermination else { return }
						let remaining = edits.filter { latestRevisions[$0.key] == revision }
						persist(remaining, onSuccess: onSuccess)
					}
				}
			}
			self?.observers[identifier] = nil
		}
	}

	/// Waits for every accepted write and its model acknowledgement. Earlier
	/// failed edits remain visible even when a later, unrelated batch succeeds.
	/// Teardown has already begun, so a failed save requires retry or an explicit
	/// decision to quit without it before the application may exit.
	func finishForTermination(
		confirmRetry: (any Error) async -> Bool
	) async {
		isFinishingTermination = true
		while true {
			let observed = submission
			_ = await tail?.result
			for observer in Array(observers.values) {
				await observer.value
			}
			guard observed == submission else { continue }
			guard let error = failures.values.first else { return }
			guard await confirmRetry(error) else { return }
			let remaining = latestEdits.filter { failures[$0.key] != nil }
			if !remaining.isEmpty {
				_ = enqueue(remaining)
			}
		}
	}
}

extension ClientConfig {
	var pendingKeychainEdits: KeychainPersistence.Edits {
		var edits: KeychainPersistence.Edits = [
			nicknamePasswordKeychainItem: pendingNicknamePassword,
			proxyPasswordKeychainItem: pendingProxyPassword,
		]
		for server in serverList {
			edits[server.keychainItem] = server.pendingServerPassword
		}
		for channel in channelList {
			edits[channel.keychainItem] = channel.pendingSecretKey
		}
		return edits.filter { $0.value != .unchanged }
	}

	var keychainItems: [KeychainItem] {
		[nicknamePasswordKeychainItem, proxyPasswordKeychainItem]
			+ serverList.map(\.keychainItem) + channelList.map(\.keychainItem)
	}

	mutating func acknowledgeKeychainEdits(_ edits: KeychainPersistence.Edits) {
		if edits[nicknamePasswordKeychainItem] == pendingNicknamePassword {
			pendingNicknamePassword = .unchanged
		}
		if edits[proxyPasswordKeychainItem] == pendingProxyPassword {
			pendingProxyPassword = .unchanged
		}
		for index in serverList.indices where edits[serverList[index].keychainItem] == serverList[index].pendingServerPassword {
			serverList[index].pendingServerPassword = .unchanged
		}
		for index in channelList.indices {
			channelList[index].acknowledgeKeychainEdits(edits)
		}
	}
}

extension ChannelConfig {
	var pendingKeychainEdits: KeychainPersistence.Edits {
		pendingSecretKey == .unchanged ? [:] : [keychainItem: pendingSecretKey]
	}

	mutating func acknowledgeKeychainEdits(_ edits: KeychainPersistence.Edits) {
		if edits[keychainItem] == pendingSecretKey {
			pendingSecretKey = .unchanged
		}
	}
}

/** Reads keychain secrets away from the main actor.

 Every `KeychainItem.password` is a synchronous `SecItemCopyMatching`.
 Connections and editors request their secrets together, off the main actor,
 and own the resulting snapshot for their session. */
nonisolated enum KeychainSecretLoader { // nonisolated: value
	@concurrent
	static func passwords(for items: [KeychainItem]) async -> [KeychainItem: String] {
		var passwords: [KeychainItem: String] = [:]

		for item in Set(items) {
			if Task.isCancelled {
				break
			}
			if let password = item.password {
				passwords[item] = password
			}
		}

		return passwords
	}

	@concurrent
	static func duplicate(_ config: ClientConfig) async -> ClientConfig {
		config.uniqueCopy()
	}
}
