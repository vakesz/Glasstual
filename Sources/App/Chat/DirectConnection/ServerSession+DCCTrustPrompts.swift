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
 put to the user as an alert and as a line they can answer by typing, and the
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
	 now. Only a new or changed certificate is asked about; a changed one is
	 never let through without the user replacing the pin. */
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
		}
	}

	/** Answers a certificate question, from its alert or from `/dcc trust`.

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
		let nickname = question.peerNickname

		if isSameConnection {
			switch answer {
			case .remember:
				saveDCCPin(question.certificate, for: nickname, replacing: false)
				printDebugInformation(toConsole: String(localized: .IRC.dccTrustRemembered(nickname)))
			case .replace:
				saveDCCPin(question.certificate, for: nickname, replacing: true)
				printDebugInformation(toConsole: String(localized: .IRC.dccTrustReplaced(nickname)))
			case .once:
				printDebugInformation(toConsole: String(localized: .IRC.dccTrustOnce(nickname)))
			case .reject:
				printDebugInformation(toConsole: String(localized: .IRC.dccTrustRejected(nickname)))
			}
		}

		for waiter in question.waiters {
			waiter.awaitingDecision(false)
			waiter.continuation.resume(returning: accepted && waiter.isCurrent())
		}
		return .answered
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
		_ certificate: DCCPeerCertificate,
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
		certificate: DCCPeerCertificate,
		from nickname: String,
		previous: [DCCPeerPin],
		in conversation: Conversation?
	) {
		let fingerprint = certificate.fingerprint
		let request: AlertRequest
		let line: String
		if let saved = previous.first {
			request = AlertRequest(
				title: PromptStrings.DCC.changedTitle(peer: nickname),
				body: PromptStrings.DCC.changedBody(
					peer: nickname, trustedOn: saved.firstTrusted, saved: saved.fingerprint, presented: fingerprint
				),
				defaultButton: PromptStrings.Action.cancel,
				alternateButton: PromptStrings.DCC.replaceSavedCertificate,
				destructiveButton: .alternate,
				cancelButton: .default,
				style: .critical
			)
			line = String(localized: .IRC.dccTrustChangedQuestion(nickname, fingerprint.formatted, id))
		} else {
			request = AlertRequest(
				title: PromptStrings.DCC.verifyTitle(peer: nickname),
				body: PromptStrings.DCC.verifyBody(peer: nickname, network: config.connectionName, fingerprint: fingerprint),
				defaultButton: PromptStrings.DCC.trustAndRemember,
				alternateButton: PromptStrings.Action.cancel,
				otherButton: PromptStrings.DCC.trustOnce
			)
			line = String(localized: .IRC.dccTrustFirstUseQuestion(nickname, fingerprint.formatted, id))
		}

		printDebugInformation(line, in: conversation)
		let isChange = previous.isEmpty == false
		output?.presentAlertSheet(request) { [weak self] outcome in
			self?.answerDCCTrustQuestion(id, with: ServerSession.trustAnswer(for: outcome.response, isChange: isChange))
		}
	}

	/** The answer an alert button stands for.

	 For a changed certificate only the alternate button, which is destructive
	 and never on Return, replaces the pin. Anything else refuses. */
	static func trustAnswer(for response: AlertResponse, isChange: Bool) -> DCCTrustAnswer {
		switch (response, isChange) {
		case (.alternate, true): .replace
		case (_, true): .reject
		case (.default, false): .remember
		case (.other, false): .once
		case (.alternate, false): .reject
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
