// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** `draft/account-registration`: creating an account from the client.

 `REGISTER` and `VERIFY` carry a new password, so they pass the same credential
 gate as SASL `PLAIN`. Before the server's welcome they go out only when the
 server advertises `before-connect`, and then `CAP END` is held until the
 outcome, so a success signs this connection in before registration completes.
 A success saves the password for SASL. */
extension ServerSession {
	/// The longest piece of a server's message shown beside a failure.
	private static let maximumServerMessageLength = 300

	/// The server's rules, from what the current offer says.
	var accountRegistrationValues: AccountRegistrationCapabilityValues {
		AccountRegistrationCapabilityValues(
			capabilityValues: capabilityNegotiation.offeredCapabilities[AccountRegistrationCapabilityValues.capabilityName] ?? []
		)
	}

	/// Whether this connection is signed in to an account.
	var isAuthenticatedToAccount: Bool {
		isCapabilityEnabled(.isIdentifiedWithSASL) || startup.authentication == .confirmed || myself?.account != nil
	}

	/// What the menu, the sheet and `/register` offer for this session.
	var accountRegistrationAvailability: AccountRegistrationAvailability {
		if config.bouncerNetwork != nil {
			return .unavailable(.bouncerNetwork)
		}
		if accountRegistration.phase.isIdle == false {
			return .unavailable(.inFlight)
		}
		guard isConnected || isConnecting else {
			return .availableAfterConnecting
		}
		if isAuthenticatedToAccount {
			return .unavailable(.alreadyAuthenticated)
		}
		if isCapabilityEnabled(.accountRegistration) {
			return .available(accountRegistrationValues)
		}
		if isLoggedIn || capabilityNegotiation.endSent {
			return .unavailable(.unsupported)
		}

		return .availableAfterConnecting
	}

	/// The problems with `request` under the rules known now.
	func accountRegistrationProblems(in request: AccountRegistrationRequest) -> [AccountRegistrationValidation] {
		AccountRegistrationValidation.problems(
			in: request,
			values: accountRegistrationAvailability.values,
			refusesCustomAccountNames: accountRegistration.refusesCustomAccountNames,
			currentNickname: userNickname,
			casefold: casefoldNickname
		)
	}

	/** Registers `request`, connecting first when the session is not connected.

	 `observer` hears every step of this one flow and nothing after it ends. */
	func registerAccount(
		_ request: AccountRegistrationRequest,
		observer: @escaping @MainActor (AccountRegistrationEvent) -> Void
	) {
		let availability = accountRegistrationAvailability

		if case let .unavailable(reason) = availability {
			observer(.failed(Self.failure(for: reason), serverMessage: nil))
			return
		}

		if let problem = accountRegistrationProblems(in: request).first {
			observer(.failed(.invalidRequest(problem), serverMessage: nil))
			return
		}

		accountRegistration.observer = observer
		routeAccountRegistration(.register(request))
	}

	/** Sends a verification code.

	 With a flow waiting for its code, the code completes it. Without one it is
	 sent for `account`, or for the current nickname, so an account registered
	 earlier can still be verified; no password is saved then. */
	func verifyAccount(
		code: String,
		account: String? = nil,
		observer: (@MainActor (AccountRegistrationEvent) -> Void)? = nil
	) {
		if let problem = AccountRegistrationValidation.codeProblem(code) {
			(observer ?? accountRegistration.observer)?(.failed(.invalidRequest(problem), serverMessage: nil))
			return
		}

		switch accountRegistration.phase {
		case let .awaitingCode(pendingAccount, request, holdsNegotiation):
			if let observer {
				accountRegistration.observer = observer
			}
			accountRegistration.codeHold?.stop()
			let command = AccountRegistrationCommand.verify(account: account ?? pendingAccount, code: code, request: request)
			if holdsNegotiation {
				sendAccountRegistrationCommand(command, timing: .beforeConnect, isRetry: false)
			} else if isLoggedIn {
				sendAccountRegistrationCommand(command, timing: .afterWelcome, isRetry: false)
			} else {
				accountRegistration.phase = .awaitingWelcome(command, isRetry: false)
			}
		case .idle:
			guard isConnected else {
				observer?(.failed(.notConnected, serverMessage: nil))
				return
			}
			accountRegistration.observer = observer
			routeAccountRegistration(.verify(account: account ?? "*", code: code, request: nil))
		default:
			observer?(.failed(.alreadyInProgress, serverMessage: nil))
		}
	}

	/// Stops the flow. The server may still finish it; nothing is saved then.
	/// Reports whether there was a flow to stop.
	@discardableResult
	func cancelAccountRegistration() -> Bool {
		guard accountRegistration.phase.isIdle == false else { return false }
		let observer = accountRegistration.observer
		endAccountRegistration()
		observer?(.cancelled)

		return true
	}

	// MARK: - Connection hooks

	/// The capability was acknowledged or withdrawn.
	func noteAccountRegistrationCapability(enabled: Bool) {
		guard enabled else {
			if accountRegistration.phase.isIdle == false {
				failAccountRegistration(.unsupported)
			}
			return
		}

		guard case let .awaitingCapability(request) = accountRegistration.phase, isLoggedIn == false else { return }

		if accountRegistrationValues.beforeConnect, capabilityNegotiation.endSent == false {
			pauseCapabilityNegotiation(.accountRegistration)
			sendAccountRegistrationCommand(.register(request), timing: .beforeConnect, isRetry: false)
		} else {
			accountRegistration.phase = .awaitingWelcome(.register(request), isRetry: false)
		}
	}

	/// The server's welcome arrived: what waited for it goes out now.
	func accountRegistrationDidReceiveWelcome() {
		switch accountRegistration.phase {
		case let .awaitingCapability(request):
			guard isCapabilityEnabled(.accountRegistration) else {
				failAccountRegistration(.unsupported)
				return
			}
			sendAccountRegistrationCommand(.register(request), timing: .afterWelcome, isRetry: false)
		case let .awaitingWelcome(command, isRetry):
			sendAccountRegistrationCommand(command, timing: .afterWelcome, isRetry: isRetry)
		case let .awaitingCode(account, request, true):
			accountRegistration.codeHold?.stop()
			accountRegistration.phase = .awaitingCode(account: account, request: request, holdsNegotiation: false)
		default:
			break
		}
	}

	/// The connection is gone: a flow still running fails.
	func accountRegistrationConnectionDidReset() {
		let observer = accountRegistration.observer
		let wasRunning = accountRegistration.phase.isIdle == false
		accountRegistration.reset()
		if wasRunning {
			observer?(.failed(.disconnected, serverMessage: nil))
		}
	}

	// MARK: - Inbound

	/// `REGISTER SUCCESS`, `REGISTER VERIFICATION_REQUIRED` and `VERIFY SUCCESS`.
	func receiveAccountRegistrationReply(_ message: Message) {
		guard message.params.count >= 2 else { return }
		let status = message.params[0].uppercased()
		let account = message.params[1]
		let serverMessage = message.params.count > 2 ? Self.sanitizedServerMessage(message.params.last ?? "") : ""

		switch status {
		case "SUCCESS":
			completeAccountRegistration(account: account, serverMessage: serverMessage)
		case "VERIFICATION_REQUIRED" where message.remoteCommand == .register:
			requireVerificationCode(account: account, serverMessage: serverMessage)
		default:
			if shouldPrintReceivedMessage(message) {
				printReply(message)
			}
		}
	}

	/** A `FAIL` for `REGISTER`, `VERIFY` or `ACCOUNT_REQUIRED`. Reports whether
	 the flow consumed it; anything else is printed the usual way. */
	func receiveAccountRegistrationFailure(_ message: Message) -> Bool {
		guard message.remoteCommand == .fail, message.params.count >= 2 else { return false }
		let command = RemoteCommand(wireName: message.params[0])
		let code = message.params[1]
		let serverMessage = Self.sanitizedServerMessage(message.params.last ?? "")

		guard command == .register || command == .verify else {
			guard code == AccountRegistrationReplyCode.accountRequired.rawValue else { return false }
			printDebugInformation(toConsole: String(localized: .AccountRegistration.accountRequiredHint))
			if accountRegistration.phase.isIdle == false {
				failAccountRegistration(.accountRequired, serverMessage: serverMessage)
			}
			return false
		}

		guard case let .sent(sentCommand, timing, isRetry) = accountRegistration.phase else { return false }

		let failure = AccountRegistrationFailure(code: code)
		accountRegistration.deadline?.stop()

		if failure == .completeConnectionRequired, isRetry == false, isLoggedIn == false {
			accountRegistration.phase = .awaitingWelcome(sentCommand, isRetry: true)
			liftAccountRegistrationHold()
		} else if failure == .invalidCode, case let .verify(account, _, request) = sentCommand {
			/* The code can be typed again; the flow stays open for it. */
			let holds = timing == .beforeConnect && capabilityNegotiation.holds.contains(.accountRegistration)
			accountRegistration.phase = .awaitingCode(account: account, request: request, holdsNegotiation: holds)
			if holds {
				startAccountRegistrationCodeHold()
			}
			accountRegistration.observer?(.failed(failure, serverMessage: serverMessage))
		} else {
			if failure == .accountNameMustBeNickname {
				accountRegistration.refusesCustomAccountNames = true
			}
			failAccountRegistration(failure, serverMessage: serverMessage)
		}

		return true
	}

	// MARK: - Timers

	func onAccountRegistrationDeadline() {
		guard accountRegistration.phase.isIdle == false else { return }
		failAccountRegistration(.timedOut)
	}

	/// The user took longer than the server's registration window allows:
	/// registration completes now, and the code goes out after the welcome.
	func onAccountRegistrationCodeHoldExpired() {
		guard case let .awaitingCode(account, request, true) = accountRegistration.phase else { return }
		accountRegistration.phase = .awaitingCode(account: account, request: request, holdsNegotiation: false)
		liftAccountRegistrationHold()
	}
}

// MARK: - Flow

private extension ServerSession {
	static func failure(for reason: AccountRegistrationUnavailability) -> AccountRegistrationFailure {
		switch reason {
		case .alreadyAuthenticated: .alreadyAuthenticated
		case .unsupported: .unsupported
		case .bouncerNetwork: .unsupportedOnBouncerNetwork
		case .inFlight: .alreadyInProgress
		}
	}

	static func sanitizedServerMessage(_ text: String) -> String {
		let line = ControlCharacterDisposition.singleLine((text as NSString).stripIRCEffects)
		guard line.count > maximumServerMessageLength else { return line }

		return String(line.prefix(maximumServerMessageLength)) + "…"
	}

	/// Decides when `command` can go out on this connection.
	func routeAccountRegistration(_ command: AccountRegistrationCommand) {
		guard isConnected || isConnecting else {
			guard case let .register(request) = command else {
				failAccountRegistration(.notConnected)
				return
			}
			accountRegistration.phase = .awaitingCapability(request)
			connect()
			if isConnecting == false, isConnected == false {
				failAccountRegistration(.notConnected)
			}
			return
		}

		if isLoggedIn {
			guard isCapabilityEnabled(.accountRegistration) else {
				failAccountRegistration(.unsupported)
				return
			}
			sendAccountRegistrationCommand(command, timing: .afterWelcome, isRetry: false)
			return
		}

		if isCapabilityEnabled(.accountRegistration) {
			if accountRegistrationValues.beforeConnect, capabilityNegotiation.endSent == false {
				pauseCapabilityNegotiation(.accountRegistration)
				sendAccountRegistrationCommand(command, timing: .beforeConnect, isRetry: false)
			} else {
				accountRegistration.phase = .awaitingWelcome(command, isRetry: false)
			}
		} else if capabilityNegotiation.endSent {
			failAccountRegistration(.unsupported)
		} else if case let .register(request) = command {
			accountRegistration.phase = .awaitingCapability(request)
		} else {
			accountRegistration.phase = .awaitingWelcome(command, isRetry: false)
		}
	}

	/** The credential gate, in the order SASL `PLAIN` asks it.

	 The user asked to register, so a certificate nobody checked is a question
	 for them even when a password was already withheld once this session. */
	func sendAccountRegistrationCommand(
		_ command: AccountRegistrationCommand,
		timing: AccountRegistrationTiming,
		isRetry: Bool
	) {
		if sessionCredentials.withholdsAccountCredentials {
			failAccountRegistration(.credentialsWithheld(.unconfiguredHost))
			return
		}
		if config.bouncerNetwork != nil {
			failAccountRegistration(.unsupportedOnBouncerNetwork)
			return
		}
		if permitsCredentialsInClear {
			writeAccountRegistrationCommand(command, timing: timing, isRetry: isRetry)
			return
		}
		guard isSecured, socket?.certificateAssurance == .unverified, hasCredentialConsent == false else {
			failAccountRegistration(.credentialsWithheld(isSecured ? .unverifiedCertificate : .plaintext))
			return
		}

		let pending = AccountRegistrationPhase.awaitingConsent(command, timing: timing, isRetry: isRetry)
		accountRegistration.phase = pending
		askToSendCredentials(
			sent: { session in
				guard session.accountRegistration.phase == pending else { return }
				session.writeAccountRegistrationCommand(command, timing: timing, isRetry: isRetry)
			},
			declined: { session in
				guard session.accountRegistration.phase == pending else { return }
				session.failAccountRegistration(.credentialsWithheld(.unverifiedCertificate))
			}
		)
	}

	func writeAccountRegistrationCommand(
		_ command: AccountRegistrationCommand,
		timing: AccountRegistrationTiming,
		isRetry: Bool
	) {
		switch command {
		case let .register(request):
			send(.register, arguments: [request.wireAccount, request.wireEmail, request.password])
		case let .verify(account, code, _):
			send(.verify, arguments: [account, code])
		}

		accountRegistration.phase = .sent(command, timing: timing, isRetry: isRetry)
		accountRegistration.deadline?.stop()
		accountRegistration.deadline = SessionTimer.once(
			after: AccountRegistrationSession.answerTimeout,
			clock: accountRegistration.clock
		) { [weak self] in
			self?.onAccountRegistrationDeadline()
		}
		accountRegistration.observer?(.started)
	}

	func requireVerificationCode(account: String, serverMessage: String) {
		guard case let .sent(.register(request), timing, _) = accountRegistration.phase else {
			printDebugInformation(toConsole: String(localized: .AccountRegistration.verificationRequired(account, serverMessage)))
			return
		}

		accountRegistration.deadline?.stop()
		let holds = timing == .beforeConnect && capabilityNegotiation.holds.contains(.accountRegistration)
		accountRegistration.phase = .awaitingCode(account: account, request: request, holdsNegotiation: holds)
		if holds {
			startAccountRegistrationCodeHold()
		}
		accountRegistration.observer?(.verificationRequired(account: account, serverMessage: serverMessage))
	}

	func startAccountRegistrationCodeHold() {
		accountRegistration.codeHold?.stop()
		accountRegistration.codeHold = SessionTimer.once(
			after: AccountRegistrationSession.codeHoldTimeout,
			clock: accountRegistration.clock
		) { [weak self] in
			self?.onAccountRegistrationCodeHoldExpired()
		}
	}

	func completeAccountRegistration(account: String, serverMessage: String) {
		guard case let .sent(command, _, _) = accountRegistration.phase else {
			/* Cancelled, or never asked for by this session: the account is the
			 server's business, but no password goes into the keychain. */
			printDebugInformation(toConsole: String(localized: .AccountRegistration.lateSuccessNotSaved(account)))
			noteAccountRegistered(account)
			return
		}

		let observer = accountRegistration.observer
		let request = command.request
		endAccountRegistration()
		noteAccountRegistered(account)

		guard let request, accountMatches(account, request: request) else {
			observer?(.succeeded(account: account, serverMessage: serverMessage, credentialsSaved: false))
			return
		}

		saveRegisteredCredentials(account: account, password: request.password) { saved in
			observer?(.succeeded(account: account, serverMessage: serverMessage, credentialsSaved: saved))
		}
	}

	/// Whether the server registered the account that was asked for.
	func accountMatches(_ account: String, request: AccountRegistrationRequest) -> Bool {
		let requested = switch request.account {
		case .currentNickname: userNickname
		case let .named(name): name
		}

		return casefoldNickname(account) == casefoldNickname(requested)
	}

	/// The connection is signed in to `account`, as if by SASL.
	func noteAccountRegistered(_ account: String) {
		if let myself {
			modify(myself) { $0.account = account }
		}
		noteAccountAuthenticated()
	}

	/** Saves the new password for SASL and signs in with it from now on.

	 The account becomes the SASL name when it differs from the one the
	 configuration would send. `completion` hears whether the keychain took it. */
	func saveRegisteredCredentials(account: String, password: String, completion: @escaping @MainActor (Bool) -> Void) {
		var edited = config
		edited.usesSASL = true
		edited.pendingNicknamePassword = .unchanged
		let configuredAccount = edited.username.nonEmpty ?? edited.nickname
		if casefoldNickname(configuredAccount) != casefoldNickname(account) {
			edited.username = account
		}
		updateConfig(edited)

		let item = config.nicknamePasswordKeychainItem
		environment.services.credentialPersistence.persist(
			[item: .set(password)],
			onSuccess: { [weak self] committed in
				self?.sessionCredentials.apply(committed)
				completion(true)
			},
			onFailure: { _ in completion(false) }
		)
	}

	func failAccountRegistration(_ failure: AccountRegistrationFailure, serverMessage: String? = nil) {
		let observer = accountRegistration.observer
		endAccountRegistration()
		observer?(.failed(failure, serverMessage: serverMessage))
	}

	/// Clears the flow and lets registration complete if it was waiting.
	func endAccountRegistration() {
		accountRegistration.stopTimers()
		accountRegistration.phase = .idle
		accountRegistration.observer = nil
		liftAccountRegistrationHold()
	}

	func liftAccountRegistrationHold() {
		guard capabilityNegotiation.holds.contains(.accountRegistration) else { return }
		resumeCapabilityNegotiation(.accountRegistration)
	}
}
