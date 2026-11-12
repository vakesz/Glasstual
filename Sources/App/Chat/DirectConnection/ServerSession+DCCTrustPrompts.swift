// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

/** Who a secure DCC connection is with, and whether the question about its
 certificate still matters.

 A transfer or chat hands this to the session when it starts a secure
 connection. The session reads it on the main actor whenever the verifier asks,
 so a peer that changed nickname is asked about under the name they use now. */
struct DCCPeerContext {
	/// The nickname the peer uses now.
	let nickname: @MainActor @Sendable () -> String
	/// Whether the transfer run or chat the connection belongs to is still the
	/// one running. A stopped transfer or closed chat is never asked about.
	let isCurrent: @MainActor @Sendable () -> Bool
	/// Told while the user is being asked, so a row can say what it waits on.
	let awaitingDecision: @MainActor @Sendable (Bool) -> Void
	/// Where the typed form of a question is printed: a chat's conversation, or
	/// `nil` for the console.
	let conversation: @MainActor @Sendable () -> Conversation?

	init(
		nickname: @escaping @MainActor @Sendable () -> String,
		isCurrent: @escaping @MainActor @Sendable () -> Bool,
		awaitingDecision: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
		conversation: @escaping @MainActor @Sendable () -> Conversation? = { nil }
	) {
		self.nickname = nickname
		self.isCurrent = isCurrent
		self.awaitingDecision = awaitingDecision
		self.conversation = conversation
	}
}

/** Deciding about the certificates secure DCC peers present.

 The verifier a secure transfer or chat runs is answered here, inside the TLS
 handshake: a pinned certificate goes ahead unasked, a new or changed one is
 put to the user as a question they answer as an alert, in the conversation or
 by typing `/dcc trust`, and the
 handshake waits for that answer. Nothing moves before it, so a receiver is
 never fed bytes from a peer nobody agreed to. */
extension ServerSession {
	/// The TLS side of a secure DCC connection on this network.
	func dccTLSConfiguration(identity: DCCLocalIdentity, context: DCCPeerContext) -> DCCTLSConfiguration {
		DCCTLSConfiguration(
			identity: identity,
			requirePeerCertificate: environment.settings.fileTransferRequiresPeerCertificate,
			verifier: DCCPeerVerifier { [weak self] certificate in
				await self?.decideDCCPeer(certificate, context: context) ?? false
			}
		)
	}

	/// This network's identity for secure connections, created the first time
	/// one is needed.
	func dccLocalIdentity() async throws -> DCCLocalIdentity {
		try await environment.services.dccIdentities.identity(forNetwork: config.uniqueIdentifier)
	}

	/** Whether the peer of a secure connection may proceed.

	 The certificate is judged against the pins for the nickname the peer uses
	 now. A new or changed certificate is asked about, and so is a missing one
	 from a nickname that has one saved; a changed one is never let through
	 without the user replacing the pin. */
	func decideDCCPeer(_ certificate: DCCPeerCertificate?, context: DCCPeerContext) async -> Bool {
		guard context.isCurrent() else { return false }
		let nickname = context.nickname()
		let network = config.uniqueIdentifier
		let caseMapping = supportInfo.caseMapping
		let store = environment.services.dccPeerCertificates
		let pins = await store.pins(network: network, nickname: nickname, caseMapping: caseMapping)
		guard context.isCurrent() else { return false }

		let verdict = DCCPeerTrust.evaluate(
			presented: certificate,
			pins: pins,
			requirePeerCertificate: environment.settings.fileTransferRequiresPeerCertificate
		)
		switch verdict {
		case let .pinned(pin):
			Task {
				try? await store.touch(pin.fingerprint, network: network, nickname: nickname, caseMapping: caseMapping, at: .now)
			}
			return true
		case .unidentified:
			return true
		case .certificateRequired, .weakKey:
			return false
		case .firstUse:
			guard let certificate else { return false }
			return await askAboutDCCCertificate(certificate, from: nickname, previous: [], context: context)
		case let .changed(previous):
			guard let certificate else { return false }
			return await askAboutDCCCertificate(certificate, from: nickname, previous: previous, context: context)
		case let .unidentifiedDespitePins(saved):
			return await askAboutDCCCertificate(nil, from: nickname, previous: saved, context: context)
		}
	}

	/** Answers a certificate question, from its alert, its card in the
	 conversation or `/dcc trust`.

	 The first answer wins. An answer that arrives after the connection the
	 question was asked on has gone refuses every waiting handshake instead of
	 acting on the new connection. */
	@discardableResult
	func answerDCCTrustQuestion(_ id: String, with answer: DCCTrustAnswer) -> DCCQuestionAnswerResult {
		guard let decision = dccDecisions.decision(withID: id) else { return .unknown }
		guard case let .trust(question) = decision.question, question.acceptableAnswers.contains(answer) else { return .wrongAnswer }
		_ = dccDecisions.remove(id: id)

		let isSameConnection = isLoggedIn && !isTerminating
			&& startup.identifier == decision.startupIdentifier
			&& socket?.uniqueIdentifier == decision.socketIdentifier
		let accepted = isSameConnection && answer != .reject

		if isSameConnection {
			noteDCCTrustAnswer(answer, to: question)
		}

		for waiter in question.waiters {
			waiter.awaitingDecision(false)
			waiter.continuation.resume(returning: accepted && waiter.isCurrent())
		}
		return .answered
	}

	/// Saves what `answer` asks to and says what it did. Only answers the
	/// question accepts reach here, so a pin is never asked of a question
	/// without a certificate.
	private func noteDCCTrustAnswer(_ answer: DCCTrustAnswer, to question: DCCTrustQuestion) {
		let nickname = question.peerNickname
		switch (answer, question.certificate) {
		case let (.remember, certificate?):
			saveDCCPin(certificate, for: nickname, replacing: false)
			printDebugInformation(toConsole: String(localized: .IRC.dccTrustRemembered(nickname)))
		case let (.replace, certificate?):
			saveDCCPin(certificate, for: nickname, replacing: true)
			printDebugInformation(toConsole: String(localized: .IRC.dccTrustReplaced(nickname)))
		case (.once, nil):
			printDebugInformation(toConsole: String(localized: .IRC.dccTrustUnidentifiedOnce(nickname)))
		case (.once, _):
			printDebugInformation(toConsole: String(localized: .IRC.dccTrustOnce(nickname)))
		case (.reject, _), (.remember, nil), (.replace, nil):
			printDebugInformation(toConsole: String(localized: .IRC.dccTrustRejected(nickname)))
		}
	}

	/// Refuses every handshake still waiting on the user and forgets every
	/// unanswered chat offer, for a connection that ended.
	func refuseDCCDecisions() {
		for decision in dccDecisions.removeAll() {
			guard case let .trust(question) = decision.question else { continue }
			for waiter in question.waiters {
				waiter.awaitingDecision(false)
				waiter.continuation.resume(returning: false)
			}
		}
	}

	// MARK: - Asking

	private func askAboutDCCCertificate(
		_ certificate: DCCPeerCertificate?,
		from nickname: String,
		previous: [DCCPeerPin],
		context: DCCPeerContext
	) async -> Bool {
		guard isLoggedIn, !isTerminating, !Task.isCancelled else { return false }
		let waiterID = UUID()
		return await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				let waiter = DCCTrustWaiter(
					id: waiterID,
					continuation: continuation,
					isCurrent: context.isCurrent,
					awaitingDecision: context.awaitingDecision
				)
				let admission = dccDecisions.addTrustWaiter(
					waiter,
					peerNickname: nickname,
					peerKey: supportInfo.casefoldString(nickname),
					certificate: certificate,
					previous: previous,
					startupIdentifier: startup.identifier,
					socketIdentifier: socket?.uniqueIdentifier,
					casefold: { [supportInfo] in supportInfo.casefoldString($0) }
				)
				switch admission {
				case let .asked(id):
					context.awaitingDecision(true)
					presentDCCTrustQuestion(id, certificate: certificate, from: nickname, previous: previous,
					                        in: context.conversation())
				case .joined:
					context.awaitingDecision(true)
				case .refused:
					printDebugInformation(toConsole: String(localized: .IRC.dccTooManyQuestions(nickname)))
					continuation.resume(returning: false)
				}
			}
		} onCancel: {
			Task { @MainActor [weak self] in
				self?.withdrawDCCTrustWaiter(waiterID)
			}
		}
	}

	/// Lets a handshake that ended stop waiting. Its question goes when nobody
	/// else waits on it, with a line saying so.
	private func withdrawDCCTrustWaiter(_ waiterID: UUID) {
		guard let (waiter, emptied) = dccDecisions.removeWaiter(waiterID) else { return }
		waiter.awaitingDecision(false)
		waiter.continuation.resume(returning: false)
		if let emptied {
			printDebugInformation(toConsole: String(localized: .IRC.dccQuestionNoLongerNeeded(emptied.id)))
		}
	}

	private func presentDCCTrustQuestion(
		_ id: String,
		certificate: DCCPeerCertificate?,
		from nickname: String,
		previous: [DCCPeerPin],
		in conversation: Conversation?
	) {
		guard let certificate else {
			presentDCCUnidentifiedPeerQuestion(id, from: nickname, saved: previous, in: conversation)
			return
		}
		let fingerprint = certificate.fingerprint
		let request = if let saved = previous.first {
			AlertRequest(
				title: PromptStrings.DCC.changedTitle(peer: nickname),
				body: PromptStrings.DCC.changedBody(
					peer: nickname, trustedOn: saved.firstTrusted, saved: saved.fingerprint, presented: fingerprint
				),
				defaultButton: PromptStrings.Action.cancel,
				alternateButton: PromptStrings.DCC.replaceSavedCertificate,
				destructiveButton: .alternate,
				cancelButton: .default,
				style: .critical,
				sensitivity: .security,
				keywords: [.default: .reject, .alternate: .replace],
				reference: id
			)
		} else {
			AlertRequest(
				title: PromptStrings.DCC.verifyTitle(peer: nickname),
				body: PromptStrings.DCC.verifyBody(peer: nickname, network: config.connectionName, fingerprint: fingerprint),
				defaultButton: PromptStrings.DCC.trustAndRemember,
				alternateButton: PromptStrings.Action.cancel,
				otherButton: PromptStrings.DCC.trustOnce,
				sensitivity: .security,
				keywords: [.default: .remember, .alternate: .reject, .other: .once],
				reference: id
			)
		}

		let kind: DCCTrustQuestion.Kind = previous.isEmpty ? .firstUse : .changed
		askDCCQuestion(id, request, in: conversation) { session, response in
			session.answerDCCTrustQuestion(id, with: ServerSession.trustAnswer(for: response, kind: kind))
		}
	}

	/** Puts a DCC question to the user and answers it with what they chose.

	 The question appears as an alert or in the conversation, and `/dcc trust`,
	 `/dcc accept` and `/dcc decline` answer it by its identifier. Taking the
	 question out of the table withdraws it. */
	func askDCCQuestion(
		_ id: String,
		_ request: AlertRequest,
		in conversation: Conversation?,
		answer: @escaping @MainActor (ServerSession, AlertResponse) -> Void
	) {
		guard let prompts else { return }
		let scope = promptScope(in: conversation, revealsMainWindow: false)
		let task = Task { [weak self, weak prompts] in
			guard let prompts else { return }
			let response = await prompts.ask(request, about: scope).response
			guard let self, !Task.isCancelled else { return }
			answer(self, response)
		}
		dccDecisions.attachPrompt(task, toDecisionWithID: id)
	}

	/** Asks about a peer that presented no certificate although one is saved
	 for its nickname. Cancel is the default; letting it in is the destructive
	 alternate, never on Return. */
	private func presentDCCUnidentifiedPeerQuestion(
		_ id: String,
		from nickname: String,
		saved: [DCCPeerPin],
		in conversation: Conversation?
	) {
		/* The verdict only asks when a certificate is saved; without one there
		 is nothing to say the peer failed to match. */
		guard let pin = saved.first else {
			answerDCCTrustQuestion(id, with: .reject)
			return
		}
		let request = AlertRequest(
			title: PromptStrings.DCC.unidentifiedTitle(peer: nickname),
			body: PromptStrings.DCC.unidentifiedBody(peer: nickname, trustedOn: pin.firstTrusted, saved: pin.fingerprint),
			defaultButton: PromptStrings.Action.cancel,
			alternateButton: PromptStrings.DCC.connectWithoutVerifying,
			destructiveButton: .alternate,
			cancelButton: .default,
			style: .critical,
			sensitivity: .security,
			keywords: [.default: .reject, .alternate: .once],
			reference: id
		)
		askDCCQuestion(id, request, in: conversation) { session, response in
			session.answerDCCTrustQuestion(id, with: ServerSession.trustAnswer(for: response, kind: .unidentified))
		}
	}

	/** The answer an alert button stands for.

	 For a changed certificate only the alternate button, which is destructive
	 and never on Return, replaces the pin; for a missing one only that button
	 lets the peer in, for this connection. Anything else refuses. */
	static func trustAnswer(for response: AlertResponse, kind: DCCTrustQuestion.Kind) -> DCCTrustAnswer {
		switch (response, kind) {
		case (.alternate, .changed): .replace
		case (.alternate, .unidentified): .once
		case (_, .changed), (_, .unidentified): .reject
		case (.default, .firstUse): .remember
		case (.other, .firstUse): .once
		case (.alternate, .firstUse): .reject
		}
	}

	private func saveDCCPin(_ certificate: DCCPeerCertificate, for nickname: String, replacing: Bool) {
		let store = environment.services.dccPeerCertificates
		let network = config.uniqueIdentifier
		let caseMapping = supportInfo.caseMapping
		let account = findUser(nickname)?.account
		Task { [weak self] in
			do {
				if replacing {
					try await store.replace(
						with: certificate, network: network, nickname: nickname,
						caseMapping: caseMapping, account: account, at: .now
					)
				} else {
					try await store.remember(
						certificate, network: network, nickname: nickname,
						caseMapping: caseMapping, account: account, at: .now
					)
				}
			} catch {
				DirectConnectionLog.transport.error(
					"Could not save a DCC peer certificate: \(error.localizedDescription, privacy: .public)"
				)
				self?.printDebugInformation(
					toConsole: String(localized: .IRC.dccTrustSaveFailed(nickname, error.localizedDescription))
				)
			}
		}
	}
}

/// What answering a DCC question by its identifier came to.
enum DCCQuestionAnswerResult: Equatable {
	case answered
	/// No question with that identifier is waiting.
	case unknown
	/// The question is waiting, but not for that kind of answer.
	case wrongAnswer
}
