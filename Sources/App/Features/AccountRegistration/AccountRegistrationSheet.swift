// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The Register Account sheet on one session.

 It owns the closure the session reports the flow through, holding the model
 weakly, and stops the flow when the sheet goes away before it finished. */
@MainActor
final class AccountRegistrationSheet: SheetSession, SessionScoped {
	private(set) var sessionId: String?
	private weak var session: ServerSession?

	let model: AccountRegistrationModel

	init(session: ServerSession) {
		self.session = session
		sessionId = session.uniqueIdentifier
		model = AccountRegistrationModel(
			networkName: session.name,
			currentNickname: session.isLoggedIn ? session.userNickname : session.config.nickname,
			values: Self.values(on: session),
			isConnected: session.isConnected,
			transportWarning: Self.transportWarning(on: session),
			replacesSavedPassword: session.sessionNicknamePassword?.isEmpty == false
		)

		super.init(window: nil)
		model.actions = actions()
		setContent(AccountRegistrationView(model: model, stop: { [weak self] in self?.model.stop() }, cancel: { [weak self] in
			self?.cancel()
		}))
	}

	override func cancel() {
		stopFlowIfRunning()
		super.cancel()
	}

	override func sheetDidEnd() {
		stopFlowIfRunning()
	}

	private func stopFlowIfRunning() {
		guard model.phase.isInFlight else { return }
		session?.cancelAccountRegistration()
	}

	private func actions() -> AccountRegistrationModel.Actions {
		AccountRegistrationModel.Actions(
			register: { [weak self] request in
				guard let self, let session else { return }
				session.registerAccount(request, observer: observer(on: session))
			},
			verify: { [weak self] code in
				guard let self, let session else { return }
				session.verifyAccount(code: code, observer: observer(on: session))
			},
			stop: { [weak self] in
				self?.session?.cancelAccountRegistration()
			},
			finish: { [weak self] in
				self?.submit()
			},
			problems: { [weak self] request in
				self?.session?.accountRegistrationProblems(in: request) ?? []
			}
		)
	}

	private func observer(on session: ServerSession) -> @MainActor (AccountRegistrationEvent) -> Void {
		{ [weak model, weak session] event in
			guard let model else { return }
			if let session {
				model.values = Self.values(on: session) ?? model.values
				model.isConnected = session.isConnected
				model.transportWarning = Self.transportWarning(on: session)
			}
			model.handle(event)
		}
	}

	/// The server's rules, once the capability is enabled.
	private static func values(on session: ServerSession) -> AccountRegistrationCapabilityValues? {
		session.isCapabilityEnabled(.accountRegistration) ? session.accountRegistrationValues : nil
	}

	/// What the credential gate would do with a password on this connection.
	private static func transportWarning(on session: ServerSession) -> AccountRegistrationModel.TransportWarning? {
		guard session.isConnected, session.permitsCredentialsInClear == false else { return nil }

		return session.isSecured ? .asksFirst : .refuses
	}
}
