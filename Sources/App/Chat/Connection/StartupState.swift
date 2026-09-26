// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// State and deadlines belong to one connection attempt. Replacing this object
/// invalidates every delayed callback from that attempt.
final class StartupState {
	enum Commands { case pending, dispatching, settling, ready }
	enum Authentication { case pending, waiting, confirmed, timedOut }
	enum Joining { case pending, scheduled, completed }

	let identifier = UUID()
	var commands = Commands.pending
	var authentication = Authentication.pending
	var joining = Joining.pending
	var requiresAuthentication = false
	var credentialTask: Task<Void, Never>?
	var channelCredentialTasks: [KeychainItem: Task<Void, Never>] = [:]
	var settlingTask: Task<Void, Never>?
	var authenticationTask: Task<Void, Never>?

	var canJoin: Bool {
		commands == .ready && (!requiresAuthentication || authentication == .confirmed || authentication == .timedOut)
	}

	func cancel() {
		credentialTask?.cancel()
		channelCredentialTasks.values.forEach { $0.cancel() }
		settlingTask?.cancel()
		authenticationTask?.cancel()
		credentialTask = nil
		channelCredentialTasks.removeAll()
		settlingTask = nil
		authenticationTask = nil
	}

	isolated deinit {
		cancel()
	}
}

/// Uses the same command parser as interactive input. Only identification
/// commands count; words inside a message or an unrelated raw command do not.
enum StartupCommandPolicy {
	static func identifiesNickServ(_ input: String) -> Bool {
		guard let parsed = ParsedUserCommand(input) else { return false }
		switch parsed.localCommand {
		case .raw, .quote, .araw, .aquote:
			return identifiesNickServOnWire(parsed.arguments.rest)
		case .msg, .smsg, .umsg:
			var arguments = parsed.arguments
			let target = arguments.next()
			return identifiesNickServOnWire("PRIVMSG \(target) :\(arguments.rest)")
		default:
			return identifiesNickServOnWire(input)
		}
	}

	static func identifiesNickServOnWire(_ line: String) -> Bool {
		guard let message = Message(line: line) else { return false }
		let body: String
		switch message.command {
		case "PRIVMSG":
			guard message.params.count == 2,
			      message.params[0].components(separatedBy: "@").first?.lowercased() == "nickserv"
			else { return false }
			body = message.params[1]
		case "NICKSERV", "NS":
			body = message.params.joined(separator: " ")
		default: return false
		}
		var tokens = CommandTokenizer(body)
		return tokens.nextToken().caseInsensitiveCompare("IDENTIFY") == .orderedSame && !tokens.nextToken().isEmpty
	}
}

extension ServerSession {
	func beginConnectCommands() {
		guard startup.commands == .pending else { return }
		let hasIdentification = config.loginCommands.contains(where: StartupCommandPolicy.identifiesNickServ)
		startup.requiresAuthentication = config.autojoinWaitsForNickServ || hasIdentification
		if isCapabilityEnabled(.isIdentifiedWithSASL) || nickServ.isConfirmed {
			startup.authentication = .confirmed
		}
		startup.commands = .dispatching
		if hasIdentification, startup.authentication != .confirmed {
			nickServ.isWaiting = true
		}
		for command in config.loginCommands {
			sendCommand(command, completeTarget: false, target: nil)
		}
		markConnectCommandsPerformed()
	}

	func noteAccountAuthenticated() {
		guard !isTerminating, !isQuitting, !isDisconnecting else { return }
		if startup.authentication != .confirmed {
			socket?.config.diagnostics?.record(.authenticated)
		}
		startup.authentication = .confirmed
		startup.authenticationTask?.cancel()
		startup.authenticationTask = nil
		nickServ.isWaiting = false
		if startup.requiresAuthentication {
			performAutoJoin()
		}
	}

	/** Called after the connection host completes the identification write.

	 The automatic join can already have started the long unattended wait,
	 because 001 usually lands before the IDENTIFY line has gone out. The
	 write is the better signal: services answer it within seconds, so its
	 short deadline replaces whatever was armed before it. */
	func noteNickServIdentificationWritten() {
		guard !isTerminating, !isQuitting, !isDisconnecting,
		      startup.requiresAuthentication,
		      startup.authentication == .pending || startup.authentication == .waiting
		else { return }
		startup.authenticationTask?.cancel()
		startup.authentication = .waiting
		nickServ.isWaiting = true
		let identifier = startup.identifier
		startup.authenticationTask = Task { [weak self] in
			do { try await Task.sleep(for: .seconds(30), clock: .continuous) } catch { return }
			guard let self else { return }
			authenticationDeadlineExpired(for: identifier)
		}
	}

	/** Starts the clock on a wait for an identification the session did not send
	 itself, and tells the user it is waiting.

	 Called where the wait actually begins — the automatic join that finds the
	 startup state unwilling to join yet. Nothing else knows that the
	 identification is never going to arrive on its own. */
	func beginUnattendedAuthenticationWait() {
		guard !isTerminating, !isQuitting, !isDisconnecting, startup.requiresAuthentication,
		      startup.authentication == .pending || startup.authentication == .waiting
		else { return }

		/* `performAutoJoin` stops the warnings on its way in, because most of
		 its callers are about to join. This one is not, so they go back on
		 every time the wait is re-entered. */
		startAutojoinDelayedWarningTimer()

		guard startup.authentication == .pending, startup.authenticationTask == nil else { return }

		startup.authentication = .waiting
		let identifier = startup.identifier
		startup.authenticationTask = Task { [weak self] in
			do {
				try await Task.sleep(
					for: .seconds(AutojoinPolicy.unattendedAuthenticationDeadline),
					clock: .continuous
				)
			} catch {
				return
			}
			guard let self else { return }
			authenticationDeadlineExpired(for: identifier)
		}
	}

	func authenticationDeadlineExpired(for identifier: UUID) {
		guard startup.identifier == identifier, startup.authentication == .waiting,
		      isLoggedIn, !isTerminating, !isQuitting, !isDisconnecting else { return }
		startup.authenticationTask?.cancel()
		startup.authenticationTask = nil
		startup.authentication = .timedOut
		nickServ.isWaiting = false
		printDebugInformation(toConsole: String(localized: .IRC.nickServIdentificationTimedOut))
		performAutoJoin()
	}

	/// Complete dispatch before evaluating any automatic join, even when the
	/// fixed-delay setting is off.
	func markConnectCommandsPerformed() {
		guard startup.commands == .pending || startup.commands == .dispatching else { return }
		let hasIdentification = config.loginCommands.contains(where: StartupCommandPolicy.identifiesNickServ)
		startup.requiresAuthentication = config.autojoinWaitsForNickServ || hasIdentification
		startup.commands = .settling
		let delay = AutojoinPolicy.delayAfterConnectCommands(
			waitsForConnectCommands: config.autojoinWaitsForConnectCommands && !hasIdentification,
			hasConnectCommands: !config.loginCommands.isEmpty,
			configuredDelay: config.autojoinDelayAfterConnectCommands
		)
		guard delay > 0 else { settleConnectCommands(); return }
		let identifier = startup.identifier
		startup.settlingTask = Task { [weak self] in
			do { try await Task.sleep(for: .seconds(delay), clock: .continuous) } catch { return }
			guard let self, startup.identifier == identifier else { return }
			settleConnectCommands()
		}
	}

	func settleConnectCommands() {
		guard startup.commands == .settling else { return }
		startup.settlingTask = nil
		startup.commands = .ready
		performAutoJoin()
	}

	func cancelConnectCommandSettling() {
		stopAutojoinTimer()
		autojoin.pendingChannels = nil
		startup.cancel()
		startup = StartupState()
	}
}
