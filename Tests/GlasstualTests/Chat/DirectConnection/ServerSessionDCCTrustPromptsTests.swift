// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// The questions a secure DCC handshake waits on: who is asked, what each
/// answer does to the pins, and which answers are refused.
@MainActor
@Suite("Secure DCC trust prompts", .timeLimit(.minutes(1)))
struct ServerSessionDCCTrustPromptsTests {
	private func makeSession(requirePeerCertificate: Bool = false) -> TestServerSession {
		var settings = ChatSettings.current()
		settings.fileTransferRequiresPeerCertificate = requirePeerCertificate
		let session = TestServerSession(
			configDictionary: ["nickname": "me"],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
		session.userNickname = "me"
		session.markAsLoggedIn()
		session.recordedOutput.answersManually = true
		return session
	}

	private func certificate() throws -> DCCPeerCertificate {
		try #require(DCCPeerCertificate(der: PeerCertificateFixture.ellipticCurve()))
	}

	private func context(
		nickname: String = "alice",
		isCurrent: @escaping @MainActor @Sendable () -> Bool = { true },
		awaiting: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
	) -> DCCPeerContext {
		DCCPeerContext(nickname: { nickname }, isCurrent: isCurrent, awaitingDecision: awaiting)
	}

	private func pins(on session: TestServerSession, for nickname: String = "alice") async -> [DCCPeerPin] {
		await session.environment.services.dccPeerCertificates.pins(
			network: session.config.uniqueIdentifier, nickname: nickname, caseMapping: .rfc1459
		)
	}

	/// Starts a decision and waits until the session has asked about it.
	private func ask(
		_ certificate: DCCPeerCertificate?,
		on session: TestServerSession,
		context: DCCPeerContext? = nil,
		questions: Int = 1
	) async -> Task<Bool, Never> {
		let context = context ?? self.context()
		let decision = Task { await session.decideDCCPeer(certificate, context: context) }
		while session.dccDecisions.decisions.count < questions, session.recordedOutput.presentedAlerts.count < questions {
			await Task.yield()
		}
		/* The question is put to the user from a task of its own. */
		while session.recordedOutput.presentedAlerts.count < min(questions, session.dccDecisions.decisions.count) {
			await Task.yield()
		}
		return decision
	}

	/// Puts the session's questions through a real router, so they can be
	/// answered the way the message field answers them. The caller keeps the
	/// router: the session holds it weakly.
	private func typedAnswers(on session: TestServerSession) -> PromptRouter {
		let router = PromptRouter(registry: PendingPromptRegistry())
		router.style = { .conversation }
		router.resolveAnchor = { $0.sessionID }
		session.environment.services.prompts = router
		return router
	}

	/// Types `line` into the message field of the session's console.
	private func type(_ line: String, on session: TestServerSession, router: PromptRouter) throws -> PromptCommandOutcome {
		let command = try #require(PromptCommand(line: line))
		return PromptCommandHandler(
			registry: router.registry, itemID: session.uniqueIdentifier, sessionID: session.uniqueIdentifier
		).perform(command)
	}

	private func waitForPinCount(_ count: Int, on session: TestServerSession) async {
		while await pins(on: session).count != count {
			await Task.yield()
		}
	}

	@Test("A first certificate is asked about with Trust and Remember as the default")
	func firstUseAlert() async throws {
		let session = makeSession()
		let decision = try await ask(certificate(), on: session)

		let alert = try #require(session.recordedOutput.presentedAlerts.first)
		#expect(alert.title == PromptStrings.DCC.verifyTitle(peer: "alice"))
		#expect(alert.defaultButton == PromptStrings.DCC.trustAndRemember)
		#expect(alert.otherButton == PromptStrings.DCC.trustOnce)
		#expect(alert.escapeButton == .alternate)
		session.answerDCCTrustQuestion("d1", with: .reject)
		#expect(await decision.value == false)
	}

	@Test("Remember pins the certificate; once lets it through without pinning", arguments: [true, false])
	func rememberOrOnce(remember: Bool) async throws {
		let session = makeSession()
		let presented = try certificate()
		let decision = await ask(presented, on: session)

		#expect(session.answerDCCTrustQuestion("d1", with: remember ? .remember : .once) == .answered)

		#expect(await decision.value)
		if remember {
			await waitForPinCount(1, on: session)
			#expect(await pins(on: session).map(\.fingerprint) == [presented.fingerprint])
		} else {
			#expect(await pins(on: session).isEmpty)
		}
	}

	@Test("A pinned certificate goes ahead without a question")
	func pinnedProceeds() async throws {
		let session = makeSession()
		let presented = try certificate()
		try await session.environment.services.dccPeerCertificates.remember(
			presented, network: session.config.uniqueIdentifier, nickname: "alice",
			caseMapping: .rfc1459, account: nil, at: .now
		)

		#expect(await session.decideDCCPeer(presented, context: context()))
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
	}

	@Test("A changed certificate's alert defaults to Cancel, and only its destructive button replaces")
	func changedAlert() async throws {
		let session = makeSession()
		let saved = try certificate()
		try await session.environment.services.dccPeerCertificates.remember(
			saved, network: session.config.uniqueIdentifier, nickname: "alice",
			caseMapping: .rfc1459, account: nil, at: .now
		)
		let presented = try certificate()
		let decision = await ask(presented, on: session)

		let alert = try #require(session.recordedOutput.presentedAlerts.first)
		#expect(alert.style == .critical)
		#expect(alert.defaultButton == PromptStrings.Action.cancel)
		#expect(alert.alternateButton == PromptStrings.DCC.replaceSavedCertificate)
		#expect(alert.destructiveButton == .alternate)
		#expect(alert.returnButton == .default)
		#expect(alert.escapeButton == .default)
		#expect(ServerSession.trustAnswer(for: .default, kind: .changed) == .reject)
		#expect(ServerSession.trustAnswer(for: .alternate, kind: .changed) == .replace)

		let completion = try #require(session.recordedOutput.presentedAlertCompletions.first)
		completion(AlertOutcome(response: .default, isSuppressed: false))

		#expect(await decision.value == false)
		#expect(await pins(on: session).map(\.fingerprint) == [saved.fingerprint])
	}

	@Test("Replacing a changed certificate makes it the only pin")
	func replaceChanged() async throws {
		let session = makeSession()
		let saved = try certificate()
		try await session.environment.services.dccPeerCertificates.remember(
			saved, network: session.config.uniqueIdentifier, nickname: "alice",
			caseMapping: .rfc1459, account: nil, at: .now
		)
		let presented = try certificate()
		let decision = await ask(presented, on: session)

		#expect(session.answerDCCTrustQuestion("d1", with: .once) == .wrongAnswer)
		#expect(session.answerDCCTrustQuestion("d1", with: .replace) == .answered)

		#expect(await decision.value)
		while await pins(on: session).map(\.fingerprint) != [presented.fingerprint] {
			await Task.yield()
		}
	}

	@Test("A first certificate cannot be answered with replace")
	func firstUseRefusesReplace() async throws {
		let session = makeSession()
		let decision = try await ask(certificate(), on: session)

		#expect(session.answerDCCTrustQuestion("d1", with: .replace) == .wrongAnswer)
		#expect(session.answerDCCTrustQuestion("d2", with: .reject) == .unknown)
		#expect(session.answerDCCTrustQuestion("d1", with: .reject) == .answered)
		#expect(session.answerDCCTrustQuestion("d1", with: .remember) == .unknown)
		#expect(await decision.value == false)
	}

	@Test("An answer after a reconnect refuses the handshake and pins nothing")
	func answerAfterReconnect() async throws {
		let session = makeSession()
		let decision = try await ask(certificate(), on: session)

		session.startup = StartupState()
		#expect(session.answerDCCTrustQuestion("d1", with: .remember) == .answered)

		#expect(await decision.value == false)
		#expect(await pins(on: session).isEmpty)
	}

	@Test("A connection that stopped being current is refused even when trusted")
	func staleConnectionIsRefused() async throws {
		let session = makeSession()
		let current = Current()
		let decision = try await ask(certificate(), on: session, context: context(isCurrent: { current.value }))

		current.value = false
		session.answerDCCTrustQuestion("d1", with: .once)

		#expect(await decision.value == false)
	}

	@Test("Two handshakes presenting the same certificate wait on one question")
	func identicalQuestionsAreCoalesced() async throws {
		let session = makeSession()
		let presented = try certificate()
		let first = await ask(presented, on: session)
		let second = Task { await session.decideDCCPeer(presented, context: context(nickname: "ALICE")) }
		while case let .trust(question)? = session.dccDecisions.decisions.first?.question, question.waiters.count < 2 {
			await Task.yield()
		}

		#expect(session.recordedOutput.presentedAlerts.count == 1)
		session.answerDCCTrustQuestion("d1", with: .once)

		#expect(await first.value)
		#expect(await second.value)
	}

	@Test("A certificate that became a change does not join the first-use question about it")
	func changedDoesNotJoinFirstUse() async throws {
		let session = makeSession()
		let presented = try certificate()
		let first = await ask(presented, on: session)
		try await session.environment.services.dccPeerCertificates.remember(
			certificate(), network: session.config.uniqueIdentifier, nickname: "alice",
			caseMapping: .rfc1459, account: nil, at: .now
		)

		let second = await ask(presented, on: session, questions: 2)

		#expect(session.dccDecisions.decisions.map(\.id) == ["d1", "d2"])
		session.answerDCCTrustQuestion("d1", with: .once)
		#expect(await first.value)
		#expect(session.answerDCCTrustQuestion("d2", with: .once) == .wrongAnswer)
		session.answerDCCTrustQuestion("d2", with: .reject)
		#expect(await second.value == false)
	}

	@Test("Past the limit of pending questions a connection is refused rather than asked")
	func pendingQuestionsAreCapped() async throws {
		let session = makeSession()
		var decisions: [Task<Bool, Never>] = []
		for index in 1 ... DCCPendingDecisions.capacity {
			try await decisions.append(ask(certificate(), on: session, context: context(nickname: "peer\(index)"), questions: index))
		}

		#expect(try await session.decideDCCPeer(certificate(), context: context(nickname: "late")) == false)
		#expect(session.recordedOutput.presentedAlerts.count == DCCPendingDecisions.capacity)

		session.refuseDCCDecisions()
		for decision in decisions {
			#expect(await decision.value == false)
		}
	}

	@Test("A disconnect refuses every waiting handshake and tells the waiters")
	func disconnectRefusesEverything() async throws {
		let session = makeSession()
		let awaiting = Current(false)
		let decision = try await ask(certificate(), on: session, context: context(awaiting: { awaiting.value = $0 }))
		#expect(awaiting.value)

		session.refuseDCCDecisions()

		#expect(await decision.value == false)
		#expect(awaiting.value == false)
		#expect(session.dccDecisions.isEmpty)
	}

	@Test("A handshake that ends while waiting withdraws its question")
	func cancelledHandshakeWithdraws() async throws {
		let session = makeSession()
		let decision = try await ask(certificate(), on: session)

		decision.cancel()

		#expect(await decision.value == false)
		while session.dccDecisions.isEmpty == false {
			await Task.yield()
		}
		let bodies = session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(bodies.contains(String(localized: .IRC.dccQuestionNoLongerNeeded("d1"))))
	}

	@Test("A peer with no certificate is let in unverified, or refused when one is required", arguments: [false, true])
	func noCertificate(required: Bool) async {
		let session = makeSession(requirePeerCertificate: required)

		#expect(await session.decideDCCPeer(nil, context: context()) == !required)
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
	}

	@Test("A nickname with a saved certificate that presents none is asked every time, with Cancel as the default")
	func noCertificateDespitePinIsAsked() async throws {
		let session = makeSession()
		let saved = try certificate()
		try await session.environment.services.dccPeerCertificates.remember(
			saved, network: session.config.uniqueIdentifier, nickname: "alice",
			caseMapping: .rfc1459, account: nil, at: .now
		)

		let first = await ask(nil, on: session)
		let alert = try #require(session.recordedOutput.presentedAlerts.first)
		#expect(alert.title == PromptStrings.DCC.unidentifiedTitle(peer: "alice"))
		#expect(alert.style == .critical)
		#expect(alert.defaultButton == PromptStrings.Action.cancel)
		#expect(alert.alternateButton == PromptStrings.DCC.connectWithoutVerifying)
		#expect(alert.otherButton == nil)
		#expect(alert.destructiveButton == .alternate)
		#expect(alert.returnButton == .default)
		#expect(alert.escapeButton == .default)
		let completion = try #require(session.recordedOutput.presentedAlertCompletions.first)
		completion(AlertOutcome(response: .default, isSuppressed: false))
		#expect(await first.value == false)

		let second = await ask(nil, on: session, questions: 2)
		#expect(session.recordedOutput.presentedAlerts.count == 2)
		#expect(session.answerDCCTrustQuestion("d2", with: .remember) == .wrongAnswer)
		#expect(session.answerDCCTrustQuestion("d2", with: .replace) == .wrongAnswer)
		let secondCompletion = try #require(session.recordedOutput.presentedAlertCompletions.last)
		secondCompletion(AlertOutcome(response: .alternate, isSuppressed: false))
		#expect(await second.value)
		#expect(await pins(on: session).map(\.fingerprint) == [saved.fingerprint])
	}

	@Test("Only the destructive button lets in a peer that presented no certificate", arguments: [
		(AlertResponse.default, DCCTrustAnswer.reject), (.alternate, .once), (.other, .reject),
	])
	func noCertificateDespitePinAnswers(_ testCase: (response: AlertResponse, answer: DCCTrustAnswer)) {
		#expect(ServerSession.trustAnswer(for: testCase.response, kind: .unidentified) == testCase.answer)
	}

	@Test("/dcc trust answers a peer that presented no certificate with once or reject only")
	func noCertificateDespitePinTypedAnswer() async throws {
		let session = makeSession()
		let router = typedAnswers(on: session)
		try await session.environment.services.dccPeerCertificates.remember(
			certificate(), network: session.config.uniqueIdentifier, nickname: "alice",
			caseMapping: .rfc1459, account: nil, at: .now
		)
		let decision = Task { await session.decideDCCPeer(nil, context: context()) }
		try await Eventually.until("the question") { router.registry.pending.count == 1 }

		let refused = try type("/dcc trust d1 remember", on: session, router: router)
		let answered = try type("/dcc trust d1 once", on: session, router: router)

		#expect(refused == .feedback(String(localized: .IRC.dccQuestionWrongAnswer("d1", "remember"))))
		#expect(answered == .answered)
		#expect(await decision.value)
		/* The question itself leaves no line behind: only what the answer did. */
		let bodies = session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(bodies.contains(String(localized: .IRC.dccTrustUnidentifiedOnce("alice"))))
	}

	@Test("A changed or missing certificate is never answered by /yes, a number or the first word that fits")
	func securityAnswersMustBeSpelledOut() async throws {
		let session = makeSession()
		let router = typedAnswers(on: session)
		try await session.environment.services.dccPeerCertificates.remember(
			certificate(), network: session.config.uniqueIdentifier, nickname: "alice",
			caseMapping: .rfc1459, account: nil, at: .now
		)
		let decision = Task { await session.decideDCCPeer(try? certificate(), context: context()) }
		try await Eventually.until("the question") { router.registry.pending.count == 1 }
		let number = try #require(router.registry.pending.first?.number)

		#expect(try type("/yes", on: session, router: router) == .feedback(
			String(localized: .InlinePrompts.spellOut(number, "replace"))
		))
		#expect(try type("/answer \(number) 2", on: session, router: router) == .feedback(
			String(localized: .InlinePrompts.spellOut(number, "replace"))
		))
		#expect(router.registry.pending.count == 1)
		#expect(try type("/no", on: session, router: router) == .answered)
		#expect(await decision.value == false)
	}

	@Test("A peer that presented no certificate does not join a question about one that did")
	func noCertificateDoesNotJoinChanged() async throws {
		let session = makeSession()
		try await session.environment.services.dccPeerCertificates.remember(
			certificate(), network: session.config.uniqueIdentifier, nickname: "alice",
			caseMapping: .rfc1459, account: nil, at: .now
		)
		let changed = try await ask(certificate(), on: session)
		let unidentified = await ask(nil, on: session, questions: 2)

		#expect(session.dccDecisions.decisions.map(\.id) == ["d1", "d2"])
		session.answerDCCTrustQuestion("d2", with: .reject)
		#expect(await unidentified.value == false)
		session.answerDCCTrustQuestion("d1", with: .reject)
		#expect(await changed.value == false)
	}

	@Test("A peer that presented no certificate is refused unasked when one is required, saved or not")
	func noCertificateRequiredDespitePin() async throws {
		let session = makeSession(requirePeerCertificate: true)
		try await session.environment.services.dccPeerCertificates.remember(
			certificate(), network: session.config.uniqueIdentifier, nickname: "alice",
			caseMapping: .rfc1459, account: nil, at: .now
		)

		#expect(await session.decideDCCPeer(nil, context: context()) == false)
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
	}

	@Test("A weak key is refused without a question")
	func weakKey() async throws {
		let session = makeSession()
		let weak = try #require(DCCPeerCertificate(der: PeerCertificateFixture.rsa(bits: 1024)))

		#expect(await session.decideDCCPeer(weak, context: context()) == false)
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
	}

	@Test("/dcc trust answers by identifier and reports what it could not answer")
	func trustCommand() async throws {
		let session = makeSession()
		let router = typedAnswers(on: session)
		let decision = Task { await session.decideDCCPeer(try? certificate(), context: context()) }
		try await Eventually.until("the question") { router.registry.pending.count == 1 }

		#expect(try type("/dcc trust d9 once", on: session, router: router) == .feedback(
			String(localized: .IRC.dccQuestionUnknown("d9"))
		))
		#expect(try type("/dcc trust d1 replace", on: session, router: router) == .feedback(
			String(localized: .IRC.dccQuestionWrongAnswer("d1", "replace"))
		))
		#expect(try type("/dcc trust d1 ONCE", on: session, router: router) == .answered)

		#expect(await decision.value)
		let bodies = session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(bodies.contains(String(localized: .IRC.dccTrustOnce("alice"))))
	}

	@Test("A script, timer or connect command cannot answer by /dcc trust")
	func untypedTrustIsRefused() async throws {
		let session = makeSession()
		let decision = try await ask(certificate(), on: session)

		session.sendCommand("dcc trust d1 remember", completeTarget: false, target: nil)

		let bodies = session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(bodies.contains(String(localized: .IRC.promptAnswerTypedOnly)))
		#expect(session.dccDecisions.isEmpty == false)
		session.answerDCCTrustQuestion("d1", with: .reject)
		#expect(await decision.value == false)
	}

	@Test("/dcc forget removes a nickname's pins on this network")
	func forgetCommand() async throws {
		let session = makeSession()
		try await session.environment.services.dccPeerCertificates.remember(
			certificate(), network: session.config.uniqueIdentifier, nickname: "alice",
			caseMapping: .rfc1459, account: nil, at: .now
		)

		session.handleDCCCommand(CommandArguments("forget Alice"), command: "DCC", targetConversation: nil)

		await waitForPinCount(0, on: session)
	}

	@Test("/dcc fingerprint prints this network's own certificate fingerprint")
	func fingerprintCommand() async throws {
		let session = makeSession()
		let identity = try await session.dccLocalIdentity()

		session.handleDCCCommand(CommandArguments("fingerprint"), command: "DCC", targetConversation: nil)

		let expected = String(localized: .IRC.dccOwnFingerprint(identity.fingerprint.formatted))
		while session.printedLines.compactMap({ ($0 as? [String: Any])?["messageBody"] as? String }).contains(expected) == false {
			await Task.yield()
		}
	}
}

/// A flag a test flips while a decision is pending.
@MainActor
private final class Current {
	var value: Bool

	init(_ value: Bool = true) {
		self.value = value
	}
}
