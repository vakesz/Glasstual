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
	case verify(account: String?, code: String)
	case invalidSyntax

	/** Reads the arguments of `/register` or `/verify`.

	 A `/register` request needs three tokens, so a lone `cancel` is never a
	 request; the password is the rest of the line and may hold spaces. */
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
			if second.isEmpty, first.caseInsensitiveCompare("cancel") == .orderedSame {
				self = .cancel
			} else if second.isEmpty || password.isEmpty {
				self = .invalidSyntax
			} else {
				self = .register(AccountRegistrationRequest(
					account: first == "*" ? .currentNickname : .named(first),
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
	func dispatchAccountRegistrationCommand(_ command: LocalCommand, parsed: ParsedUserCommand) {
		switch AccountRegistrationCommandRequest(command: command, arguments: parsed.arguments.rest) {
		case .describe:
			printAccountRegistrationSummary()
		case .cancel:
			if cancelAccountRegistration() == false {
				printDebugInformation(toConsole: String(localized: .AccountRegistration.nothingToCancel))
			}
		case let .register(request):
			printDebugInformation(toConsole: String(localized: .AccountRegistration.registeringAccount(
				request.account == .currentNickname ? userNickname : request.wireAccount
			)))
			registerAccount(request, observer: transcriptAccountRegistrationObserver(savesPassword: true))
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
