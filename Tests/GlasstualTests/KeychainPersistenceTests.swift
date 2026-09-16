/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Security
import Testing

@MainActor
@Suite("Credential persistence", .timeLimit(.minutes(1)))
struct KeychainPersistenceTests {
	@Test("Quit waits for accepted settings preparation and the final configuration commit")
	func settingsSaveIncludesPreparationAndCommit() async {
		let persistence = KeychainPersistence { _ in }
		let (preparation, prepared) = AsyncStream<Void>.makeStream()
		let (commit, committed) = AsyncStream<Void>.makeStream()
		let (stages, stage) = AsyncStream<Int>.makeStream()
		var configurationSaved = false
		var quitFinished = false
		let save = persistence.submitSettingsSave {
			stage.yield(1)
			for await _ in preparation {}
			let item = KeychainItem.nicknamePassword(UUID().uuidString)
			do {
				try await persistence.enqueue([item: .set("secret")], retainsFailureForTermination: false).value
			} catch {
				Issue.record(error)
				return false
			}
			stage.yield(2)
			for await _ in commit {}
			configurationSaved = true
			return true
		}
		var iterator = stages.makeAsyncIterator()
		#expect(await iterator.next() == 1)
		let pendingSaves = persistence.waitForSettingsSaves()
		let quit = Task {
			let succeeded = await pendingSaves.value
			quitFinished = true
			return succeeded
		}
		prepared.finish()
		#expect(await iterator.next() == 2)
		#expect(!configurationSaved)
		#expect(!quitFinished)
		committed.finish()
		#expect(await quit.value)
		#expect(configurationSaved)
		await save.value
	}

	@Test("An active settings failure cancels quit without poisoning a later quit")
	func settingsSaveFailurePreventsTermination() async {
		let persistence = KeychainPersistence { _ in }
		let (gate, release) = AsyncStream<Void>.makeStream()
		let save = persistence.submitSettingsSave {
			for await _ in gate {}
			return false
		}
		let quit = persistence.waitForSettingsSaves()
		release.finish()
		#expect(await !quit.value)
		await save.value
		#expect(await persistence.waitForSettingsSaves().value)
	}

	@Test("Quit includes a new settings save accepted while an earlier save is pending")
	func settingsSaveAcceptedDuringWait() async {
		let persistence = KeychainPersistence { _ in }
		let (firstGate, releaseFirst) = AsyncStream<Void>.makeStream()
		let (secondGate, releaseSecond) = AsyncStream<Void>.makeStream()
		let first = persistence.submitSettingsSave {
			for await _ in firstGate {}
			return true
		}
		let quit = persistence.waitForSettingsSaves()
		let second = persistence.submitSettingsSave {
			for await _ in secondGate {}
			return false
		}
		releaseSecond.finish()
		await second.value
		releaseFirst.finish()
		await first.value
		#expect(await !quit.value)
	}

	@Test("A failed editor attempt is not retried without its configuration at termination")
	func failedEditorSaveDoesNotBecomeTerminationRetry() async {
		let writer = CredentialWriteRecorder(failFirst: true)
		let persistence = KeychainPersistence { try await writer.write($0) }
		let edits: KeychainPersistence.Edits = [.nicknamePassword(UUID().uuidString): .set("draft")]
		await #expect(throws: KeychainWriteError.self) {
			try await persistence.enqueue(edits, retainsFailureForTermination: false).value
		}
		var askedToRetry = false
		await persistence.finishForTermination { _ in
			askedToRetry = true
			return false
		}
		#expect(!askedToRetry)
		#expect(await writer.batches == [edits])
	}

	@Test("Escape dismisses a credential failure without retrying a save")
	func retryAlertKeyboardRoles() {
		let failure = KeychainWriteError(status: errSecInteractionNotAllowed)
		let retry = KeychainAlerts.failureAlert(failure, canRetry: true)
		#expect(retry.escapeButton == .alternate)
		#expect(retry.alternateButton == PromptStrings.Action.cancel)
		let information = KeychainAlerts.failureAlert(failure, canRetry: false)
		#expect(information.escapeButton == .default)
		#expect(information.alternateButton == nil)
	}

	@Test("An injected failure presenter can retry the failed write and acknowledge it")
	func failurePresentationRetriesWrite() async {
		let writer = CredentialWriteRecorder(failFirst: true)
		let (acknowledgements, acknowledged) = AsyncStream<Void>.makeStream()
		defer { acknowledged.finish() }
		var failures = 0
		let persistence = KeychainPersistence(write: { try await writer.write($0) }, reportFailure: { error, retry in
			#expect(error is KeychainWriteError)
			failures += 1
			retry()
		})
		let edits: KeychainPersistence.Edits = [.nicknamePassword(UUID().uuidString): .set("retry me")]
		persistence.persist(edits) { committed in
			#expect(committed == edits)
			acknowledged.yield(())
		}
		var iterator = acknowledgements.makeAsyncIterator()
		_ = await iterator.next()
		#expect(failures == 1)
		#expect(await writer.batches == [edits, edits])
		await persistence.finishForTermination { _ in
			Issue.record("The retried write already succeeded")
			return false
		}
	}

	@Test("A failed write keeps pending edits and a later retry can commit them")
	func failurePreservesEditsForRetry() async throws {
		let writer = CredentialWriteRecorder(failFirst: true)
		let persistence = KeychainPersistence { try await writer.write($0) }
		var config = ClientConfig()
		config.pendingNicknamePassword = .set("replacement")
		config.pendingProxyPassword = .cleared
		let edits = config.pendingKeychainEdits

		await #expect(throws: KeychainWriteError.self) {
			try await persistence.enqueue(edits).value
		}
		#expect(config.pendingKeychainEdits == edits)

		try await persistence.enqueue(edits).value
		config.acknowledgeKeychainEdits(edits)
		#expect(config.pendingKeychainEdits.isEmpty)
		#expect(await writer.batches == [edits, edits])
	}

	@Test("Writes retain submission order across suspension and failure")
	func orderedWrites() async throws {
		let (gate, release) = AsyncStream<Void>.makeStream()
		let (started, didStart) = AsyncStream<Void>.makeStream()
		let writer = CredentialWriteRecorder(failFirst: true, gate: gate, started: didStart)
		let persistence = KeychainPersistence { try await writer.write($0) }
		let item = KeychainItem.nicknamePassword(UUID().uuidString)
		let first = persistence.enqueue([item: .set("first")])
		var iterator = started.makeAsyncIterator()
		_ = await iterator.next()
		let second = persistence.enqueue([item: .set("second")])
		release.finish()
		_ = await first.result
		try await second.value
		#expect(await writer.events == ["start", "finish", "start", "finish"])
		#expect(await writer.batches == [[item: .set("first")], [item: .set("second")]])
	}

	@Test("An older completion cannot acknowledge a newer secret edit")
	func newerEditsSurviveOldCompletion() {
		var config = ClientConfig()
		config.pendingNicknamePassword = .set("old")
		var channel = ChannelConfig()
		channel.pendingSecretKey = .set("old key")
		config.channelList = [channel]
		let oldEdits = config.pendingKeychainEdits
		config.pendingNicknamePassword = .set("new")
		config.channelList[0].pendingSecretKey = .cleared
		config.acknowledgeKeychainEdits(oldEdits)
		#expect(config.pendingNicknamePassword == .set("new"))
		#expect(config.channelList[0].pendingSecretKey == .cleared)
	}

	@Test("A saved clear remains a resolved absence in the session cache")
	func clearedCredentialDoesNotFallBack() {
		let item = KeychainItem.channelSecretKey(UUID().uuidString)
		var credentials = SessionCredentials()
		credentials.install([item: "old"], items: [item], applying: [:])
		credentials.apply([item: .cleared])
		#expect(credentials.hasResolved(item))
		#expect(credentials.password(for: item) == nil)
		credentials.forget()
		#expect(!credentials.hasResolved(item))
	}

	private nonisolated enum EndpointRequest: CaseIterable { // nonisolated: value
		case configured, userCommand, serverRedirect, stsUpgrade
	}

	@Test("Credential refresh preserves the requested endpoint", arguments: EndpointRequest.allCases, [false, true])
	private func credentialRefreshKeepsEndpoint(request: EndpointRequest, acknowledgePassword: Bool) async throws {
		let fixture = ClientEnvironmentFixture()
		let origin = Server(serverAddress: "origin.invalid")
		var config = ClientConfig()
		config.serverList = [origin, Server(serverAddress: "fallback.invalid")]
		let client = Client(config: config, environment: fixture.environment)
		client.config.pendingNicknamePassword = .set("pending")
		let explicit: PendingIRCEndpoint? = switch request {
		case .configured: nil
		case .userCommand:
			PendingIRCEndpoint(host: "command.invalid", port: 6697, secured: true, origin: origin, reason: .userCommand)
		case .serverRedirect:
			PendingIRCEndpoint(host: "redirect.invalid", port: 7000, secured: true, origin: origin, reason: .serverRedirect)
		case .stsUpgrade:
			PendingIRCEndpoint(host: origin.serverAddress, port: 7001, secured: true, origin: origin, reason: .stsUpgrade)
		}
		client.pendingEndpoint = explicit
		var printed: [String] = []
		client.linePrintObserver = { printed.append($0.messageBody) }
		let (firstGate, releaseFirst) = AsyncStream<Void>.makeStream()
		let (secondGate, releaseSecond) = AsyncStream<Void>.makeStream()
		let (started, didStart) = AsyncStream<Int>.makeStream()
		defer {
			client.disconnect()
			releaseFirst.finish()
			releaseSecond.finish()
			didStart.finish()
		}
		let loader = CredentialLoaderGate(first: firstGate, second: secondGate, started: didStart)
		client.credentialLoader = { await loader.load($0) }
		client.connect()
		var iterator = started.makeAsyncIterator()
		#expect(await iterator.next() == 1)
		let selectedIndex = client.lastServerSelected
		if acknowledgePassword {
			let edits = client.config.pendingKeychainEdits
			client.config.acknowledgeKeychainEdits(edits)
		} else {
			client.config.connectionName = "Renamed during credential lookup"
		}
		releaseFirst.finish()
		#expect(await iterator.next() == 2)
		let expected = String(localized: .IRC.connectingToOnPort(
			explicit?.host ?? origin.serverAddress,
			String(explicit?.port ?? origin.serverPort)
		))
		#expect(printed.filter { $0 == expected }.count == 2)
		#expect(client.lastServerSelected == selectedIndex)
		#expect(client.pendingEndpoint == nil)
		#expect(client.server == (request == .configured || request == .stsUpgrade ? origin : nil))
		#expect(client.socket == nil)
		let preparation = try #require(client.pendingCredentialTask)
		client.disconnect()
		releaseSecond.finish()
		await preparation.value
		#expect(client.socket == nil)
	}

	@Test("Retrying a configured server uses its edited address and current list position")
	func configuredRetryUsesLatestEndpoint() throws {
		let fixture = ClientEnvironmentFixture()
		var original = Server(serverAddress: "original.invalid")
		let fallback = Server(serverAddress: "fallback.invalid")
		var config = ClientConfig()
		config.serverList = [original, fallback]
		let client = Client(config: config, environment: fixture.environment)
		#expect(try #require(client.takeConnectionEndpoint()).serverAddress == original.serverAddress)
		original.serverAddress = "edited.invalid"
		original.serverPort = 7001
		original.prefersSecuredConnection = true
		client.config.serverList = [fallback, original]
		let retry = try #require(client.takeConnectionEndpoint(retryingServerIdentifier: original.uniqueIdentifier))
		#expect(retry.serverAddress == "edited.invalid")
		#expect(retry.serverPort == 7001)
		#expect(retry.connectionPrefersSecuredConnection)
		#expect(client.lastServerSelected == 1)
		#expect(try #require(client.takeConnectionEndpoint()).serverAddress == fallback.serverAddress)
	}

	@Test("Changing endpoint during credential loading restarts the complete connection attempt")
	func configurationChangeDuringCredentialLoad() async throws {
		let fixture = ClientEnvironmentFixture()
		var config = ClientConfig()
		var server = Server()
		server.serverAddress = "old.example"
		config.serverList = [server]
		let client = Client(config: config, environment: fixture.environment)
		let (firstGate, releaseFirst) = AsyncStream<Void>.makeStream()
		let (secondGate, releaseSecond) = AsyncStream<Void>.makeStream()
		let (started, didStart) = AsyncStream<Int>.makeStream()
		let loader = CredentialLoaderGate(first: firstGate, second: secondGate, started: didStart)
		client.credentialLoader = { await loader.load($0) }
		client.connect()
		var iterator = started.makeAsyncIterator()
		#expect(await iterator.next() == 1)
		var replacement = Server()
		replacement.serverAddress = "new.example"
		client.config.serverList = [replacement]
		releaseFirst.finish()
		#expect(await iterator.next() == 2)
		#expect(client.socket == nil)
		#expect(client.server?.serverAddress == "new.example")
		#expect(client.sessionNicknamePassword == nil)
		let preparation = try #require(client.pendingCredentialTask)
		client.disconnect()
		releaseSecond.finish()
		await preparation.value
		#expect(client.socket == nil)
	}

	@Test("Disconnect cancels credential preparation before opening a socket")
	func disconnectDuringCredentialLoad() async throws {
		let fixture = ClientEnvironmentFixture()
		var config = ClientConfig()
		var server = Server()
		server.serverAddress = "127.0.0.1"
		config.serverList = [server]
		let client = Client(config: config, environment: fixture.environment)
		let (gate, release) = AsyncStream<Void>.makeStream()
		let (started, didStart) = AsyncStream<Void>.makeStream()
		client.credentialLoader = { items in
			didStart.yield(())
			for await _ in gate {}
			return Dictionary(items.map { ($0, "stale") }, uniquingKeysWith: { _, newest in newest })
		}
		client.connect()
		let preparation = try #require(client.pendingCredentialTask)
		var iterator = started.makeAsyncIterator()
		_ = await iterator.next()
		#expect(client.isConnecting)
		#expect(client.socket == nil)
		client.disconnect()
		release.finish()
		await preparation.value
		#expect(!client.isConnecting)
		#expect(client.socket == nil)
		#expect(client.sessionNicknamePassword == nil)
	}
}

private actor CredentialWriteRecorder {
	private let failFirst: Bool
	private let gate: AsyncStream<Void>?
	private let started: AsyncStream<Void>.Continuation?
	private(set) var batches: [[KeychainItem: PendingKeychainSecret]] = []
	private(set) var events: [String] = []

	init(failFirst: Bool, gate: AsyncStream<Void>? = nil, started: AsyncStream<Void>.Continuation? = nil) {
		self.failFirst = failFirst
		self.gate = gate
		self.started = started
	}

	func write(_ edits: [KeychainItem: PendingKeychainSecret]) async throws {
		let first = batches.isEmpty
		batches.append(edits)
		events.append("start")
		if first {
			started?.yield(())
			if let gate {
				for await _ in gate {}
			}
		}
		events.append("finish")
		if first, failFirst {
			throw KeychainWriteError(status: errSecInteractionNotAllowed)
		}
	}
}

private actor CredentialLoaderGate {
	private let first: AsyncStream<Void>
	private let second: AsyncStream<Void>
	private let started: AsyncStream<Int>.Continuation
	private var count = 0

	init(first: AsyncStream<Void>, second: AsyncStream<Void>, started: AsyncStream<Int>.Continuation) {
		self.first = first
		self.second = second
		self.started = started
	}

	func load(_ items: [KeychainItem]) async -> [KeychainItem: String] {
		count += 1
		started.yield(count)
		let gate = count == 1 ? first : second
		for await _ in gate {}
		return Dictionary(items.map { ($0, "stale") }, uniquingKeysWith: { _, newest in newest })
	}
}
