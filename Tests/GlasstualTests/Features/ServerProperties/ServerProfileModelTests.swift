// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Profile pane", .timeLimit(.minutes(1)))
struct ServerProfileModelTests {
	private func readySession(offer: String = "batch draft/metadata-2") throws -> TestServerSession {
		let session = try makeMetadataSession(offer: offer, joined: false)
		try session.receive(":irc.example.net BATCH +own metadata ada")
		try session.receive("@batch=own :irc.example.net METADATA ada display-name * :Ada")
		try session.receive(":irc.example.net BATCH -own")
		return session
	}

	private func sets(_ session: TestServerSession) -> [String] {
		session.wireLines.filter { $0.hasPrefix("METADATA * SET") }
	}

	@Test("The pane says why it cannot edit, and is ready once the profile is loaded")
	func availability() throws {
		let disconnected = makeRegistrationSession()
		disconnected.setConnectionTransportForTesting(.idle)
		#expect(ServerProfileModel(session: disconnected).availability == .disconnected)

		let unsupported = try makeMetadataSession(offer: "batch", joined: false)
		#expect(ServerProfileModel(session: unsupported).availability == .unsupported)

		let loading = try makeMetadataSession(joined: false)
		let model = ServerProfileModel(session: loading)
		#expect(model.availability == .loading)

		try loading.receive(":irc.example.net 376 ada :End of MOTD")
		try loading.receive(":irc.example.net METADATA ada color * :#123456")
		try loading.receive(":irc.example.net BATCH +x metadata #nothing")
		try loading.receive(":irc.example.net BATCH -x")
		#expect(model.availability == .ready)
		#expect(model.displayName.isEmpty)
	}

	@Test("Only the changed keys are sent, and an emptied field removes its key")
	func onlyChangedKeys() throws {
		let session = try readySession()
		let model = ServerProfileModel(session: session)
		#expect(model.displayName == "Ada")
		#expect(model.hasChanges == false)

		model.displayName = ""
		model.usesColor = true
		model.color = ProfileColor(red: 0x11, green: 0x22, blue: 0x33)
		model.update()

		#expect(sets(session).sorted() == ["METADATA * SET color #112233", "METADATA * SET display-name"])
		#expect(model.statusText == String(localized: .ServerProperties.profileUpdating))
	}

	@Test("A value longer than max-value-bytes is refused before sending")
	func validation() throws {
		let session = try readySession(offer: "batch draft/metadata-2=max-value-bytes=8")
		let model = ServerProfileModel(session: session)

		model.displayName = "Ada Lovelace"
		model.avatarURL = "ftp://example.org/a.png"
		model.update()

		#expect(sets(session).isEmpty)
		#expect(model.validationMessage(for: .displayName) == String(localized: .ServerProperties.profileErrorTooLong(8)))
		#expect(model.validationMessage(for: .avatar) != nil)
		#expect(model.focusRequest == .displayName)
	}

	@Test("A rate limit shows the wait, and the server's rewritten value lands in the field")
	func rateLimitAndRewrite() async throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = try readySession()
		session.metadata.clock = clock.timerClock
		let model = ServerProfileModel(session: session)

		model.displayName = "  E2E   Display "
		model.update()
		try session.receive(":irc.example.net FAIL METADATA RATE_LIMITED * display-name 2 :Slow down")
		#expect(model.statusText == String(localized: .ServerProperties.profileWaiting(2)))

		await clock.advance(by: 2.1)
		#expect(sets(session).count == 2)
		try session.receive(":irc.example.net 761 ada * display-name * :E2E Display")

		#expect(model.displayName == "E2E Display")
		#expect(model.statusText == String(localized: .ServerProperties.profileUpdatedRewritten))
		#expect(session.config.serverProfile?.displayName == "E2E   Display")
	}

	@Test("Removing asks first and then sends CLEAR")
	func removalConfirms() async throws {
		let session = try readySession()
		session.recordedOutput.responseAnswer = .alternate
		let model = ServerProfileModel(session: session)

		model.confirmRemoval()
		try await Eventually.until("the answer") { session.wireLines.last == "METADATA * CLEAR" }

		#expect(session.recordedOutput.responseRequests.count == 1)
	}

	@Test("Declining the removal sends nothing")
	func removalDeclined() async throws {
		let session = try readySession()
		session.recordedOutput.responseAnswer = .default
		let model = ServerProfileModel(session: session)

		model.confirmRemoval()
		try await Eventually.until("the answer") { session.recordedOutput.responseRequests.count == 1 }
		await Task.yield()

		#expect(session.wireLines.contains("METADATA * CLEAR") == false)
	}

	@Test("A disconnect mid-update keeps the edits and drops what was waiting")
	func disconnectMidUpdate() async throws {
		let session = try readySession()
		let model = ServerProfileModel(session: session)

		model.displayName = "New Name"
		model.update()
		session.resetAllPropertyValues()
		try await Eventually.until("the pane to notice") { model.availability == .disconnected }

		#expect(model.displayName == "New Name")
		#expect(model.isUpdating == false)
	}
}
