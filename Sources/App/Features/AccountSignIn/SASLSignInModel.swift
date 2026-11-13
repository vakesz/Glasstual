// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

/** The Sign In Again sheet's state: who the connection is signed in as, the
 mechanisms the server offers and whether each can sign in, and how the
 exchange the sheet started is going. The session runs the exchange; this
 follows it. */
@MainActor
@Observable
final class SASLSignInModel {
	/// One mechanism the server offers. A reason means it cannot be chosen.
	struct Option: Identifiable, Hashable {
		let mechanism: SASLMechanism
		let unavailableReason: String?

		var id: SASLMechanism {
			mechanism
		}
	}

	enum State: Equatable {
		case ready
		case inProgress
		case succeeded(String)
		case failed(String)
	}

	private(set) var account: String?
	private(set) var options: [Option] = []
	var selection = SASLMechanismChoice.automatic
	private(set) var state = State.ready

	@ObservationIgnored private weak var session: ServerSession?
	@ObservationIgnored private let notifications = NotificationSubscriptions()
	@ObservationIgnored private var hasStarted = false

	init(session: ServerSession) {
		self.session = session
		refresh()
		notifications.observe(SASLExchangeStatusDidChange.self, of: session) { [weak self] _ in
			self?.refresh()
		}
		notifications.observe(SessionCapabilitiesDidChange.self, of: session) { [weak self] _ in
			self?.refresh()
		}
	}

	/// Whether the exchange the sheet started has ended, one way or the other.
	var isFinished: Bool {
		switch state {
		case .succeeded, .failed: true
		case .ready, .inProgress: false
		}
	}

	var canSignIn: Bool {
		state != .inProgress && session?.canBeginSASLReauthentication == true
	}

	func refresh() {
		guard let session else { return }
		account = session.identity.account
		options = Self.options(for: session)
		if case let .mechanism(mechanism) = selection, options.contains(where: { $0.mechanism == mechanism }) == false {
			selection = .automatic
		}
		guard hasStarted else { return }
		switch session.sasl.status {
		case .idle:
			break
		case .inProgress:
			state = .inProgress
		case let .succeeded(account, mechanism):
			state = .succeeded(String(localized: .AccountSignIn.signedInWith(account ?? session.userNickname, mechanism.wireName)))
		case let .failed(reason):
			state = .failed(reason)
		}
	}

	func signIn() {
		guard let session else { return }
		let explicit: SASLMechanism? = if case let .mechanism(mechanism) = selection {
			mechanism
		} else {
			nil
		}
		hasStarted = true
		if let refusal = session.beginSASLReauthentication(using: explicit) {
			state = .failed(refusal.localizedDescription)
		} else {
			state = .inProgress
			refresh()
		}
	}

	/// The offered mechanisms the session knows, strongest first. A `sasl`
	/// value without names offers every mechanism.
	static func options(for session: ServerSession) -> [Option] {
		guard let offered = session.offeredSASLMechanisms else { return [] }
		let known = offered.isEmpty ? SASLMechanism.defaultOrder : SASLPolicy.knownMechanisms(in: offered)
		return SASLMechanism.defaultOrder.filter(known.contains).map { mechanism in
			let reason: String? = if case let .unavailable(reason) = session.saslAvailability(of: mechanism) {
				SASLAvailabilityText.describe(reason)
			} else {
				nil
			}
			return Option(mechanism: mechanism, unavailableReason: reason)
		}
	}
}
