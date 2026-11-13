// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Security
import Testing

@MainActor
@Suite("Credential termination", .timeLimit(.minutes(1)))
struct KeychainTerminationTests {
	@Test("Termination waits for queued writes and model acknowledgements")
	func waitsForAcceptedWrites() async {
		let (gate, release) = AsyncStream<Void>.makeStream()
		let writer = TerminationCredentialWriter(gate: gate)
		let persistence = KeychainPersistence { try await writer.write($0) }
		let first = KeychainItem.nicknamePassword(UUID().uuidString)
		let second = KeychainItem.proxyPassword(UUID().uuidString)
		var acknowledgements = 0
		persistence.persist([first: .set("one")]) { _ in acknowledgements += 1 }
		persistence.persist([second: .cleared]) { _ in acknowledgements += 1 }
		let completion = Task {
			await persistence.finishForTermination { _ in
				Issue.record("Successful writes must not ask to retry")
				return false
			}
			#expect(await writer.batches.count == 2)
			#expect(acknowledgements == 2)
		}
		release.finish()
		await completion.value
	}

	@Test("A later successful batch does not hide an earlier failed password")
	func earlierFailureIsRetried() async throws {
		let writer = TerminationCredentialWriter(failFirst: true)
		let persistence = KeychainPersistence { try await writer.write($0) }
		let first = KeychainItem.nicknamePassword(UUID().uuidString)
		let second = KeychainItem.proxyPassword(UUID().uuidString)
		_ = await persistence.enqueue([first: .set("unsaved")]).result
		try await persistence.enqueue([second: .set("saved")]).value
		var decisions = 0
		await persistence.finishForTermination { error in
			#expect(error is KeychainWriteError)
			decisions += 1
			return decisions == 1
		}
		#expect(decisions == 1)
		#expect(await writer.batches == [[first: .set("unsaved")], [second: .set("saved")], [first: .set("unsaved")]])
	}

	@Test("A newer edit during a quit failure prompt supersedes the failed value")
	func retryCannotRestoreOldPassword() async {
		let writer = TerminationCredentialWriter(failFirst: true)
		let persistence = KeychainPersistence { try await writer.write($0) }
		let item = KeychainItem.nicknamePassword(UUID().uuidString)
		_ = await persistence.enqueue([item: .set("old")]).result
		var decisions = 0
		await persistence.finishForTermination { _ in
			decisions += 1
			_ = await persistence.enqueue([item: .set("new")]).result
			return true
		}
		#expect(decisions == 1)
		#expect(await writer.batches == [[item: .set("old")], [item: .set("new")]])
	}

	@Test("Quitting with unsaved passwords requires an explicit failure decision")
	func explicitQuitWithoutSaving() async {
		let writer = TerminationCredentialWriter(failFirst: true)
		let persistence = KeychainPersistence { try await writer.write($0) }
		let item = KeychainItem.nicknamePassword(UUID().uuidString)
		_ = persistence.enqueue([item: .set("unsaved")])
		var decisions = 0
		await persistence.finishForTermination { error in
			let alert = KeychainAlerts.terminationFailureAlert(error)
			#expect(alert.escapeButton == .default)
			#expect(alert.alternateButton == String(localized: .Prompts.keychainQuitWithoutSaving))
			decisions += 1
			return false
		}
		#expect(decisions == 1)
		#expect(await writer.batches.count == 1)
	}
}

private actor TerminationCredentialWriter {
	private let gate: AsyncStream<Void>?
	private let failFirst: Bool
	private(set) var batches: [KeychainPersistence.Edits] = []

	init(gate: AsyncStream<Void>? = nil, failFirst: Bool = false) {
		self.gate = gate
		self.failFirst = failFirst
	}

	func write(_ edits: KeychainPersistence.Edits) async throws {
		let first = batches.isEmpty
		if first, let gate {
			for await _ in gate {}
		}
		batches.append(edits)
		if first, failFirst {
			throw KeychainWriteError(status: errSecInteractionNotAllowed)
		}
	}
}
