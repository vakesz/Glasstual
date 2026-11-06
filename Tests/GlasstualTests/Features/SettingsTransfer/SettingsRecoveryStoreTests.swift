// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// How many local recovery backups are kept, and which.
struct SettingsRecoveryStoreTests {
	private func makeDirectory() -> URL {
		FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
			.appendingPathComponent("Backups", isDirectory: true)
	}

	private let archive = SettingsArchive(values: [:], unset: [], sessions: [], source: .localRecovery)

	@Test("Only the newest five backups survive a save, and the one just written is among them")
	func pruning() async throws {
		let directory = makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
		let store = SettingsRecoveryStore(directory: directory)
		var saved: [SettingsRecoveryBackup] = []

		for _ in 0 ..< SettingsRecoveryStore.retentionCount + 2 {
			try await saved.append(store.save(archive))
		}

		let remaining = try await store.backups()

		#expect(remaining.count == SettingsRecoveryStore.retentionCount)
		#expect(remaining.contains { $0.url == saved.last?.url })
	}

	@Test("Fewer backups than the limit are all kept")
	func underTheLimit() async throws {
		let directory = makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
		let store = SettingsRecoveryStore(directory: directory)

		for _ in 0 ..< 3 {
			_ = try await store.save(archive)
		}

		#expect(try await store.backups().count == 3)
	}

	@Test("Files that are not this store's archives are never pruned")
	func foreignFilesSurvive() async throws {
		let directory = makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
		let store = SettingsRecoveryStore(directory: directory)
		_ = try await store.save(archive)
		let foreign = ["notes.txt", "Other-1.plist", "Configuration-1.txt"].map { directory.appendingPathComponent($0) }

		for url in foreign {
			try Data("keep".utf8).write(to: url)
		}

		for _ in 0 ..< SettingsRecoveryStore.retentionCount + 2 {
			_ = try await store.save(archive)
		}

		#expect(foreign.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
	}

	@Test("The retention count is five")
	func retention() {
		#expect(SettingsRecoveryStore.retentionCount == 5)
	}
}
