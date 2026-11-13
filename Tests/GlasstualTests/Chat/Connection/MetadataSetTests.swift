// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Setting the user's own metadata", .timeLimit(.minutes(1)))
struct MetadataSetTests {
	private final class Outcomes {
		var values: [MetadataSetOutcome] = []
	}

	@Test("SET sends an empty value as a trailing parameter and a removal without one")
	func setShapes() throws {
		let session = try makeMetadataSession(joined: false)

		session.setOwnMetadata(key: "display-name", value: "Ada Lovelace")
		#expect(session.wireLines.last == "METADATA * SET display-name :Ada Lovelace")
		session.setOwnMetadata(key: "avatar", value: "")
		#expect(session.wireLines.last == "METADATA * SET avatar :")
		session.setOwnMetadata(key: "color", value: nil)
		#expect(session.wireLines.last == "METADATA * SET color")
	}

	@Test("The server's value is what is stored, and 766 clears")
	func storedValueIsTheServers() throws {
		let session = try makeMetadataSession()
		let outcomes = Outcomes()

		session.setOwnMetadata(key: "display-name", value: "  Ada  ") { outcomes.values.append($0) }
		try session.receive(":irc.example.net 761 ada * display-name * :Ada")
		#expect(outcomes.values == [.stored("Ada")])
		#expect(session.metadata.ownWireValues["display-name"] == "Ada")
		#expect(session.myself?.profile.displayName?.text == "Ada")

		session.setOwnMetadata(key: "display-name", value: nil) { outcomes.values.append($0) }
		try session.receive(":irc.example.net 766 ada * display-name :key not set")
		#expect(outcomes.values.last == .stored(nil))
		#expect(session.metadata.ownWireValues["display-name"] == nil)
	}

	@Test("RATE_LIMITED retries after the server's delay with the latest value")
	func rateLimitedWithDelay() async throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = try makeMetadataSession(joined: false)
		session.metadata.clock = clock.timerClock
		let outcomes = Outcomes()

		session.setOwnMetadata(key: "display-name", value: "First") { outcomes.values.append($0) }
		try session.receive(":irc.example.net FAIL METADATA RATE_LIMITED * display-name 3 :Slow down")
		#expect(outcomes.values == [.rateLimited(retryAfter: 3)])

		session.setOwnMetadata(key: "display-name", value: "Second") { outcomes.values.append($0) }
		let sets = { session.wireLines.filter { $0.hasPrefix("METADATA * SET") } }
		#expect(sets().count == 1)

		await clock.advance(by: 3.1)
		#expect(sets().last == "METADATA * SET display-name Second")

		try session.receive(":irc.example.net 761 ada * display-name * :Second")
		#expect(outcomes.values.last == .stored("Second"))
	}

	@Test("RATE_LIMITED without a delay backs off and gives up after four tries")
	func rateLimitedWithoutDelay() async throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = try makeMetadataSession(joined: false)
		session.metadata.clock = clock.timerClock
		let outcomes = Outcomes()

		session.setOwnMetadata(key: "color", value: "#000000") { outcomes.values.append($0) }
		for delay in [5, 10, 20, 40] {
			try session.receive(":irc.example.net FAIL METADATA RATE_LIMITED * color * :Slow down")
			#expect(outcomes.values.last == .rateLimited(retryAfter: delay))
			await clock.advance(by: TimeInterval(delay) + 0.1)
		}
		try session.receive(":irc.example.net FAIL METADATA RATE_LIMITED * color * :Slow down")

		#expect(outcomes.values.last == .failed(.rateLimitExhausted))
	}

	@Test(
		"Refusals of a set reach its observer",
		arguments: [
			("LIMIT_REACHED * :Too many keys", MetadataFailure.limitReached(maximumKeys: 5)),
			("VALUE_INVALID :Bad value", .valueInvalid(maximumBytes: nil)),
			("KEY_NO_PERMISSION * display-name :No", .keyNoPermission),
			("KEY_INVALID display-name :No", .keyInvalid),
		]
	)
	func setRefusals(_ testCase: (line: String, failure: MetadataFailure)) throws {
		let session = try makeMetadataSession(offer: "batch draft/metadata-2=max-keys=5", joined: false)
		let outcomes = Outcomes()

		session.setOwnMetadata(key: "display-name", value: "Ada") { outcomes.values.append($0) }
		try session.receive(":irc.example.net FAIL METADATA \(testCase.line)")

		#expect(outcomes.values == [.failed(testCase.failure)])
	}

	@Test("KEY_NOT_SET for a removal counts as removed")
	func keyNotSetOnRemoval() throws {
		let session = try makeMetadataSession(joined: false)
		let outcomes = Outcomes()

		session.setOwnMetadata(key: "avatar", value: nil) { outcomes.values.append($0) }
		try session.receive(":irc.example.net FAIL METADATA KEY_NOT_SET * avatar :Not set")

		#expect(outcomes.values == [.stored(nil)])
	}

	@Test("CLEAR is answered by a batch of 766 and completes once")
	func clearBatch() throws {
		let session = try makeMetadataSession()
		try session.receive(":irc.example.net METADATA ada display-name * :Ada")
		var completions: [MetadataFailure?] = []

		session.clearOwnMetadata { completions.append($0) }
		#expect(session.wireLines.last == "METADATA * CLEAR")
		try session.receive(":irc.example.net BATCH +c metadata ada")
		try session.receive("@batch=c :irc.example.net 766 ada ada display-name :key not set")
		try session.receive(":irc.example.net BATCH -c")

		#expect(completions.count == 1)
		#expect(session.metadata.ownWireValues.isEmpty)
		#expect(session.config.serverProfile == ServerProfilePreference())
	}

	@Test("A remembered profile is set again where the server's copy differs")
	func rememberedProfileIsReapplied() throws {
		var settings = ChatSettings.current()
		settings.showsServerProfiles = true
		let session = TestServerSession(
			configDictionary: [:], nicknamePassword: nil, fixture: ChatEnvironmentFixture(settings: settings)
		)
		session.config.nickname = "ada"
		session.config.serverProfile = ServerProfilePreference(displayName: "Ada", color: "#112233")
		session.setConnectionTransportForTesting(.connected)
		session.userNickname = "ada"
		try session.negotiate("batch draft/metadata-2")
		try session.receive(":irc.example.net 001 ada :Welcome")
		try session.receive(":irc.example.net BATCH +own metadata ada")
		try session.receive("@batch=own :irc.example.net METADATA ada color * :#112233")
		try session.receive(":irc.example.net BATCH -own")

		#expect(session.wireLines.contains("METADATA * SET display-name Ada"))
		#expect(session.wireLines.contains { $0.contains("SET color") } == false)
		#expect(session.wireLines.contains { $0.contains("SET avatar") } == false)
	}

	@Test("Setting a key remembers it in the server's configuration")
	func setRemembers() throws {
		let session = try makeMetadataSession(joined: false)

		session.setOwnMetadata(key: "display-name", value: "Ada")

		#expect(session.config.serverProfile?.displayName == "Ada")
	}

	@Test("Without the capability or a connection the set is refused")
	func unavailable() {
		let session = makeRegistrationSession()
		var outcomes: [MetadataSetOutcome] = []

		session.setOwnMetadata(key: "display-name", value: "Ada") { outcomes.append($0) }

		#expect(outcomes == [.failed(.unsupported)])
	}
}
