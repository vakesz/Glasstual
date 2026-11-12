// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// What `/register` and `/verify` were asked to do.
nonisolated enum AccountRegistrationCommandRequest: Equatable {
	/// `/register` alone: say what this server accepts.
	case describe
	case cancel
	case register(AccountRegistrationRequest)
	/// An account and an email without a password: the password is asked for
	/// in a secure field, so it never has to be typed on the command line.
	case askPassword(account: AccountRegistrationRequest.AccountName, email: String?)
	case verify(account: String?, code: String)
	case invalidSyntax

	/** Reads the arguments of `/register` or `/verify`.

	 A `/register` request names an account and an email, so a lone `cancel` is
	 never a request; the password is the rest of the line and may hold spaces.
	 Without one, the password is asked for in a secure field. */
	init(command: LocalCommand, arguments: String) {
		var tokenizer = CommandTokenizer(arguments)
		let first = tokenizer.nextToken()

		switch command {
		case .register:
			if first.isEmpty {
				self = .describe
				return
			}
			let second = tokenizer.nextToken()
			let password = String(tokenizer.remainder)
			let account: AccountRegistrationRequest.AccountName = first == "*" ? .currentNickname : .named(first)
			if second.isEmpty, first.caseInsensitiveCompare("cancel") == .orderedSame {
				self = .cancel
			} else if second.isEmpty || first.caseInsensitiveCompare("cancel") == .orderedSame {
				self = .invalidSyntax
			} else if password.isEmpty {
				self = .askPassword(account: account, email: second == "*" ? nil : second)
			} else {
				self = .register(AccountRegistrationRequest(
					account: account,
					email: second == "*" ? nil : second,
					password: password
				))
			}
		case .verify:
			let second = tokenizer.nextToken()
			if first.isEmpty || tokenizer.remainder.isEmpty == false {
				self = .invalidSyntax
			} else if second.isEmpty {
				self = .verify(account: nil, code: first)
			} else {
				self = .verify(account: first, code: second)
			}
		default:
			self = .invalidSyntax
		}
	}
}

extension ServerSession {
	/// `/register`, `/verify` and `/metadata`: the user's account and profile.
	func dispatchAccountCommand(_ command: LocalCommand, parsed: ParsedUserCommand) {
		if command == .metadata {
			dispatchMetadataCommand(parsed)
		} else {
			dispatchAccountRegistrationCommand(command, parsed: parsed)
		}
	}

	func dispatchAccountRegistrationCommand(_ command: LocalCommand, parsed: ParsedUserCommand) {
		switch AccountRegistrationCommandRequest(command: command, arguments: parsed.arguments.rest) {
		case .describe:
			printAccountRegistrationSummary()
		case .cancel:
			if cancelAccountRegistration() == false {
				printDebugInformation(toConsole: String(localized: .AccountRegistration.nothingToCancel))
			}
		case let .register(request):
			dispatchAccountRegistrationRequest(request)
		case let .askPassword(account, email):
			askForRegistrationPassword(account: account, email: email)
		case let .verify(account, code):
			let savesPassword = accountRegistration.phase.request != nil
			verifyAccount(
				code: code,
				account: account,
				observer: accountRegistration.observer ?? transcriptAccountRegistrationObserver(savesPassword: savesPassword)
			)
		case .invalidSyntax:
			printInvalidSyntaxMessage(for: parsed.command)
		}
	}

	/** Asks for the new account's password in a secure field, as an alert or
	 in the console, and registers with it. The password goes from the field to
	 the registration and nowhere else: not the transcript, not input history. */
	private func askForRegistrationPassword(account: AccountRegistrationRequest.AccountName, email: String?) {
		let name = account == .currentNickname ? userNickname : (AccountRegistrationRequest(
			account: account, email: email, password: ""
		).wireAccount)
		requestAnswer(AlertRequest(
			title: String(localized: .AccountRegistration.passwordPromptTitle(name)),
			body: String(localized: .AccountRegistration.passwordPromptBody(config.connectionName)),
			defaultButton: String(localized: .AccountRegistration.passwordPromptRegister),
			alternateButton: PromptStrings.Action.cancel,
			field: .secure(placeholder: String(localized: .AccountRegistration.passwordPromptPlaceholder)),
			keywords: [.default: .submit, .alternate: .cancel]
		), boundToConnection: false, unattended: .alternate) { session, answer in
			guard answer.response == .default, let password = answer.text, password.isEmpty == false else { return }
			session.dispatchAccountRegistrationRequest(AccountRegistrationRequest(
				account: account, email: email, password: password
			))
		}
	}

	private func dispatchAccountRegistrationRequest(_ request: AccountRegistrationRequest) {
		printDebugInformation(toConsole: String(localized: .AccountRegistration.registeringAccount(
			request.account == .currentNickname ? userNickname : request.wireAccount
		)))
		registerAccount(request, observer: transcriptAccountRegistrationObserver(savesPassword: true))
	}

	/// What `/register` alone prints: the server's rules, or why it cannot.
	func printAccountRegistrationSummary() {
		switch accountRegistrationAvailability {
		case let .available(values):
			for line in Self.accountRegistrationSummary(values) {
				printDebugInformation(toConsole: line)
			}
		case .availableAfterConnecting:
			printDebugInformation(toConsole: String(localized: .AccountRegistration.summaryAfterConnecting))
		case let .unavailable(reason):
			let failure: AccountRegistrationFailure = switch reason {
			case .alreadyAuthenticated: .alreadyAuthenticated
			case .unsupported: .unsupported
			case .bouncerNetwork: .unsupportedOnBouncerNetwork
			case .inFlight: .alreadyInProgress
			}
			printDebugInformation(toConsole: failure.localizedDescription)
		}
	}

	/// The lines that describe a server's registration rules, in order.
	static func accountRegistrationSummary(_ values: AccountRegistrationCapabilityValues) -> [String] {
		var lines = [String(localized: .AccountRegistration.summaryHeader)]

		lines.append(values.customAccountName
			? String(localized: .AccountRegistration.summaryAnyAccountName)
			: String(localized: .AccountRegistration.summaryNicknameAccountName))
		lines.append(values.emailRequired
			? String(localized: .AccountRegistration.summaryEmailRequired)
			: String(localized: .AccountRegistration.summaryEmailOptional))
		if let minimum = values.minimumPasswordBytes {
			lines.append(String(localized: .AccountRegistration.summaryPasswordMinimum(minimum)))
		}
		if let maximum = values.maximumPasswordBytes {
			lines.append(String(localized: .AccountRegistration.summaryPasswordMaximum(maximum)))
		}
		if values.beforeConnect {
			lines.append(String(localized: .AccountRegistration.summaryBeforeConnect))
		}
		lines.append(String(localized: .AccountRegistration.summaryUsage))

		return lines
	}

	/** Prints a command-started flow into the server console.

	 `savesPassword` says whether a success stores a password: a `/verify` for
	 an account registered earlier has none to store. */
	private func transcriptAccountRegistrationObserver(
		savesPassword: Bool
	) -> @MainActor (AccountRegistrationEvent) -> Void {
		{ [weak self] event in
			guard let self else { return }

			switch event {
			case .started:
				break
			case let .verificationRequired(account, serverMessage):
				if serverMessage.isEmpty == false {
					printDebugInformation(toConsole: String(localized: .AccountRegistration.serverMessage(serverMessage)))
				}
				printDebugInformation(toConsole: String(localized: .AccountRegistration.verificationRequiredCommandHint(account)))
			case let .succeeded(account, _, credentialsSaved):
				let text = if credentialsSaved {
					String(localized: .AccountRegistration.registeredAndSaved(account))
				} else if savesPassword {
					String(localized: .AccountRegistration.registeredNotSaved(account))
				} else {
					String(localized: .AccountRegistration.verifiedWithoutPassword(account))
				}
				printDebugInformation(toConsole: text)
			case let .failed(failure, serverMessage):
				printDebugInformation(toConsole: String(localized: .AccountRegistration.registrationFailed(
					failure.localizedDescription
				)))
				if let serverMessage, serverMessage.isEmpty == false {
					printDebugInformation(toConsole: String(localized: .AccountRegistration.serverMessage(serverMessage)))
				}
			case .cancelled:
				printDebugInformation(toConsole: String(localized: .AccountRegistration.registrationCancelled))
			}
		}
	}
}
