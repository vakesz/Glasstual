// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// How the user answers a question about a secure DCC peer's certificate.
enum DCCTrustAnswer: String, CaseIterable, Sendable {
	/// Trust the certificate and pin it for later connections.
	case remember
	/// Trust the certificate for the connection that presented it.
	case once
	/// Replace the pins for the nickname with the certificate presented now.
	case replace
	/// Refuse the connection.
	case reject

	/// Parses the word typed after `/dcc trust <id>`.
	init?(typed: String) {
		self.init(rawValue: typed.lowercased())
	}
}

/// A connection waiting in a TLS handshake for the user's answer about the
/// peer's certificate.
struct DCCTrustWaiter {
	let id: UUID
	let continuation: CheckedContinuation<Bool, Never>
	/// Whether the transfer run or chat the connection belongs to is still
	/// the one the question is about.
	let isCurrent: @MainActor @Sendable () -> Bool
	/// Told when the question is asked and when it is settled.
	let awaitingDecision: @MainActor @Sendable (Bool) -> Void
}

/** A question about a secure DCC peer's certificate.

 Two connections from the same peer presenting the same certificate wait on
 one question, so the user answers once for both. */
struct DCCTrustQuestion {
	/// What the question is about.
	enum Kind: Equatable {
		/// A certificate from a nickname with none saved.
		case firstUse
		/// A certificate other than the ones saved for the nickname.
		case changed
		/// No certificate at all, from a nickname with one saved.
		case unidentified
	}

	let peerNickname: String
	/// What the peer presented; `nil` when it presented nothing although a
	/// certificate is saved for its nickname.
	let certificate: DCCPeerCertificate?
	/// The pins that no longer match; empty when the peer has none.
	let previous: [DCCPeerPin]
	var waiters: [DCCTrustWaiter]

	var kind: Kind {
		if certificate == nil {
			.unidentified
		} else if previous.isEmpty {
			.firstUse
		} else {
			.changed
		}
	}

	/// The answers that fit: a changed certificate is never trusted once, and
	/// a missing one can only be let in for this connection or refused.
	var acceptableAnswers: Set<DCCTrustAnswer> {
		switch kind {
		case .firstUse: [.remember, .once, .reject]
		case .changed: [.replace, .reject]
		case .unidentified: [.once, .reject]
		}
	}
}

/// A direct chat offer waiting for Accept or Decline.
struct DCCChatOfferQuestion {
	let sender: String
	let offer: DirectChatOffer
}

/** The questions about DCC connections this session is waiting on the user
 for, each under a short identifier the user can type to answer it.

 A question records the connection it was asked on, because an answer that
 arrives after a reconnect must not act on the new one. The table is bounded,
 so a peer cannot pile up questions behind the user's back; past the bound a
 connection is refused rather than asked about. Chat offers have a bound of
 their own, above what the offer throttle lets in at once, so unanswered
 offers never crowd out a question about a connection the user started. */
struct DCCPendingDecisions {
	/// How many certificate questions may wait at once.
	static let capacity = 8
	/// How many chat offers may wait for Accept or Decline at once.
	static let chatOfferCapacity = 32

	enum Question {
		case trust(DCCTrustQuestion)
		case chatOffer(DCCChatOfferQuestion)
	}

	struct Decision {
		let id: String
		var question: Question
		let startupIdentifier: UUID
		let socketIdentifier: String?
	}

	/// What adding a waiter came to.
	enum Admission: Equatable {
		/// A new question, which has to be put to the user.
		case asked(id: String)
		/// An identical question was already pending; the waiter joined it.
		case joined(id: String)
		/// The table is full and the connection has to be refused.
		case refused
	}

	private var nextNumber = 1
	private(set) var decisions: [Decision] = []

	var isEmpty: Bool {
		decisions.isEmpty
	}

	func decision(withID id: String) -> Decision? {
		decisions.first { $0.id == id.lowercased() }
	}

	/** Puts a waiter on the question about `certificate` from `peerKey`,
	 asking a new one only when no identical question is pending. A `nil`
	 certificate is the question about a peer that presented none. */
	mutating func addTrustWaiter(
		_ waiter: DCCTrustWaiter,
		peerNickname: String,
		peerKey: String,
		certificate: DCCPeerCertificate?,
		previous: [DCCPeerPin],
		startupIdentifier: UUID,
		socketIdentifier: String?,
		casefold: (String) -> String
	) -> Admission {
		if let index = decisions.firstIndex(where: {
			guard case let .trust(question) = $0.question else { return false }
			/* Only a question asked under the same verdict: a waiter whose
			 certificate has become a change must not be let through by an answer
			 given to a first use, nor the reverse. */
			return question.certificate?.fingerprint == certificate?.fingerprint
				&& casefold(question.peerNickname) == peerKey
				&& $0.startupIdentifier == startupIdentifier
				&& question.previous.map(\.fingerprint) == previous.map(\.fingerprint)
		}), case var .trust(question) = decisions[index].question {
			question.waiters.append(waiter)
			decisions[index].question = .trust(question)
			return .joined(id: decisions[index].id)
		}
		guard count(of: .trust) < Self.capacity else {
			return .refused
		}
		let question = DCCTrustQuestion(
			peerNickname: peerNickname, certificate: certificate, previous: previous, waiters: [waiter]
		)
		return .asked(id: add(.trust(question), startupIdentifier: startupIdentifier, socketIdentifier: socketIdentifier))
	}

	/// Records a chat offer, or `nil` when the table is full.
	mutating func addChatOffer(
		_ question: DCCChatOfferQuestion,
		startupIdentifier: UUID,
		socketIdentifier: String?
	) -> String? {
		guard count(of: .chatOffer) < Self.chatOfferCapacity else { return nil }
		return add(.chatOffer(question), startupIdentifier: startupIdentifier, socketIdentifier: socketIdentifier)
	}

	/// Takes the decision out of the table. The first answer wins: a later one
	/// finds nothing.
	mutating func remove(id: String) -> Decision? {
		guard let index = decisions.firstIndex(where: { $0.id == id.lowercased() }) else { return nil }
		return decisions.remove(at: index)
	}

	/** Takes one waiter out of its question, for a connection that ended
	 while it waited. The question goes with its last waiter, and is handed back
	 so the caller can say it is no longer needed. */
	mutating func removeWaiter(_ waiterID: UUID) -> (waiter: DCCTrustWaiter, emptied: Decision?)? {
		for index in decisions.indices {
			guard case var .trust(question) = decisions[index].question,
			      let position = question.waiters.firstIndex(where: { $0.id == waiterID })
			else { continue }
			let waiter = question.waiters.remove(at: position)
			if question.waiters.isEmpty {
				return (waiter, decisions.remove(at: index))
			}
			decisions[index].question = .trust(question)
			return (waiter, nil)
		}
		return nil
	}

	/// Empties the table, for a session whose connection ended.
	mutating func removeAll() -> [Decision] {
		defer { decisions.removeAll() }
		return decisions
	}

	private enum Kind {
		case trust
		case chatOffer
	}

	private func count(of kind: Kind) -> Int {
		decisions.count { decision in
			switch (decision.question, kind) {
			case (.trust, .trust), (.chatOffer, .chatOffer): true
			case (.trust, .chatOffer), (.chatOffer, .trust): false
			}
		}
	}

	private mutating func add(_ question: Question, startupIdentifier: UUID, socketIdentifier: String?) -> String {
		let id = "d\(nextNumber)"
		nextNumber += 1
		decisions.append(Decision(
			id: id, question: question, startupIdentifier: startupIdentifier, socketIdentifier: socketIdentifier
		))
		return id
	}
}
