// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Settings session archive validation")
struct SettingsSessionArchiveTests {
	@Test("An imported autojoin delay is rejected before the legacy decoder can clamp it",
	      arguments: [-1.0, 60.001, Double.greatestFiniteMagnitude])
	func rejectsOutOfRangeAutojoinDelay(_ delay: Double) async throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		let before = try session.liveSnapshot()
		var configuration = ServerConfig(connectionName: "Imported server")
		configuration.autojoinDelayAfterConnectCommands = delay
		let archive = SettingsArchive.snapshot(from: fixture.stores, sessions: [configuration])
		let url = try fixture.write(archive.encoded())

		await session.prepareImport(from: url)

		#expect(session.errorMessage != nil)
		#expect(session.preview == nil)
		#expect(try session.liveSnapshot().hasSameConfiguration(as: before))
		#expect(try await session.recoveryStore.backups().isEmpty)
	}

	@Test("An accepted autojoin delay survives the archive unchanged", arguments: [0.0, 3.5, 60.0])
	func preservesAcceptedAutojoinDelay(_ delay: Double) throws {
		var configuration = ServerConfig(connectionName: "Imported server")
		configuration.autojoinDelayAfterConnectCommands = delay
		let archive = SettingsArchive(values: [:], unset: [], sessions: [configuration])

		let decoded = try SettingsArchive.decode(archive.encoded())

		#expect(decoded.sessions?.first?.autojoinDelayAfterConnectCommands == delay)
	}
}
