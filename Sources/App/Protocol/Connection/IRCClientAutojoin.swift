/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation

enum IRCClientAutojoinPolicy {
	static let delayedWarningInterval: TimeInterval = 90
	static let maximumDelayedWarningCount: UInt = 3

	/** How long the client waits for an identification nothing in the session
	 is actually sending.

	 `noteNickServIdentificationWritten()` starts a thirty second deadline when
	 the client itself wrote the IDENTIFY line. Turning on "wait for NickServ"
	 without any login command that identifies — a bouncer that authenticates
	 for you, a server that recognises the certificate — armed nothing, so the
	 join list sat unsent for the rest of the session. This deadline covers that
	 wait, and is measured in warning intervals so that the user has been told
	 what is being waited for before the client gives up and joins anyway. */
	static let unattendedAuthenticationDeadline: TimeInterval =
		delayedWarningInterval * TimeInterval(maximumDelayedWarningCount)

	/** How long to pause after the connect commands were sent before joining.

	 This legacy delay applies to lists without NickServ identification.
	 Zero disables it; identification uses its own confirmation deadline. */
	static func delayAfterConnectCommands(
		waitsForConnectCommands: Bool,
		hasConnectCommands: Bool,
		configuredDelay: TimeInterval
	) -> TimeInterval {
		guard waitsForConnectCommands, hasConnectCommands else { return 0 }
		return max(0, min(configuredDelay, ClientConfigDefaults.maximumAutojoinConnectCommandDelay))
	}
}

/// State and deadlines belong to one connection attempt. Replacing this object
/// invalidates every delayed callback from that attempt.
final class IRCStartupCoordinator {
	enum Commands { case pending, dispatching, settling, ready }
	enum Authentication { case pending, waiting, confirmed, timedOut }
	enum Joining { case pending, scheduled, completed }

	let identifier = UUID()
	var commands = Commands.pending
	var authentication = Authentication.pending
	var joining = Joining.pending
	var requiresAuthentication = false
	var settlingTask: Task<Void, Never>?
	var authenticationTask: Task<Void, Never>?

	var canJoin: Bool {
		commands == .ready && (!requiresAuthentication || authentication == .confirmed || authentication == .timedOut)
	}

	func cancel() {
		settlingTask?.cancel()
		authenticationTask?.cancel()
		settlingTask = nil
		authenticationTask = nil
	}

	isolated deinit {
		settlingTask?.cancel()
		authenticationTask?.cancel()
	}
}

/// Uses the same command parser as interactive input. Only identification
/// commands count; words inside a message or an unrelated raw command do not.
enum IRCStartupCommandPolicy {
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
		guard let message = Message(line: line, on: nil) else { return false }
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

@MainActor
extension IRCClient {
	func beginConnectCommands() {
		guard startup.commands == .pending else { return }
		startup.requiresAuthentication = config.autojoinWaitsForNickServ
			|| config.loginCommands.contains(where: IRCStartupCommandPolicy.identifiesNickServ)
		if isCapabilityEnabled(.isIdentifiedWithSASL) || userIsIdentifiedWithNickServ {
			startup.authentication = .confirmed
		}
		startup.commands = .dispatching
		if config.loginCommands.contains(where: IRCStartupCommandPolicy.identifiesNickServ),
		   startup.authentication != .confirmed
		{
			isWaitingForNickServ = true
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
		isWaitingForNickServ = false
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
		isWaitingForNickServ = true
		let identifier = startup.identifier
		startup.authenticationTask = Task { [weak self] in
			do { try await Task.sleep(for: .seconds(30), clock: .continuous) } catch { return }
			guard let self else { return }
			authenticationDeadlineExpired(for: identifier)
		}
	}

	/** Starts the clock on a wait for an identification the client did not send
	 itself, and tells the user it is waiting.

	 Called where the wait actually begins — the automatic join that finds the
	 startup coordinator unwilling to join yet. Nothing else knows that the
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
					for: .seconds(IRCClientAutojoinPolicy.unattendedAuthenticationDeadline),
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
		isWaitingForNickServ = false
		printDebugInformation(toConsole: IRCConnectionStrings.nickServIdentificationTimedOut)
		performAutoJoin()
	}
}

@MainActor
public extension IRCClient {
	func startAutojoinTimer() {
		guard !autojoinTimer.isActive else { return }
		let interval = startup.requiresAuthentication ? 0 : environment.preferences.autojoinDelayAfterIdentification
		guard interval > 0 else {
			onAutojoinTimer()
			return
		}
		autojoinTimer.start(interval, repeats: false)
	}

	func stopAutojoinTimer() {
		guard autojoinTimer.isActive else { return }
		autojoinTimer.stop()
	}

	/** Joins every pending channel at once.

	 One JOIN per line that fits the server's budget, and the connection host's
	 flood control paces the lines; the two-channels-every-few-seconds throttle
	 this used to run on top of that only made a long channel list take tens of
	 seconds to arrive. */
	func onAutojoinTimer() {
		guard isLoggedIn, !isTerminating, !isQuitting, !isDisconnecting,
		      isAutojoining, let channels = channelsToAutojoin else { return }
		channelsToAutojoin = nil
		joinChannels(channels)
		isAutojoining = false
		isAutojoined = true
	}

	/// Complete dispatch before evaluating any automatic join, even when the
	/// legacy fixed-delay preference is off.
	func markConnectCommandsPerformed() {
		guard startup.commands == .pending || startup.commands == .dispatching else { return }
		startup.requiresAuthentication = config.autojoinWaitsForNickServ
			|| config.loginCommands.contains(where: IRCStartupCommandPolicy.identifiesNickServ)
		startup.commands = .settling
		let hasIdentification = config.loginCommands.contains(where: IRCStartupCommandPolicy.identifiesNickServ)
		let delay = IRCClientAutojoinPolicy.delayAfterConnectCommands(
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
		channelsToAutojoin = nil
		startup.cancel()
		startup = IRCStartupCoordinator()
	}

	/// Forgets a join list that has not been sent yet.
	func cancelPendingAutojoin() {
		channelsToAutojoin = nil
		isAutojoining = false
	}

	func startAutojoinDelayedWarningTimer() {
		guard !autojoinDelayedWarningTimer.isActive else { return }
		autojoinDelayedWarningTimer.start(IRCClientAutojoinPolicy.delayedWarningInterval, repeats: true)
	}

	func stopAutojoinDelayedWarningTimer() {
		guard autojoinDelayedWarningTimer.isActive else { return }
		autojoinDelayedWarningTimer.stop()
	}

	func onAutojoinDelayedWarningTimer() {
		guard isLoggedIn, !config.hideAutojoinDelayedWarnings,
		      autojoinDelayedWarningCount < IRCClientAutojoinPolicy.maximumDelayedWarningCount
		else {
			stopAutojoinDelayedWarningTimer()
			return
		}

		autojoinDelayedWarningCount += 1
		let text = IRCConnectionStrings.autojoinDelayedForIdentification
		printDebugInformation(toConsole: text)
		if let channel = output?.selectedChannel(on: self) {
			printDebugInformation(text, in: channel)
		}
	}

	func performAutoJoin() {
		performAutoJoin(initiatedByUser: false)
	}

	func performAutoJoin(initiatedByUser: Bool) {
		guard isLoggedIn, !isTerminating, !isQuitting, !isDisconnecting, !isAutojoining else { return }
		stopAutojoinDelayedWarningTimer()

		if !initiatedByUser {
			guard !isAutojoined else { return }
			if isConnectedToZNC, config.zncIgnoreConfiguredAutojoin {
				isAutojoined = true
				return
			}
			guard startup.canJoin else {
				beginUnattendedAuthenticationWait()
				return
			}
		}

		let channels = channelList.filter { $0.isChannel && !$0.isActive && $0.config.autoJoin }
		guard !channels.isEmpty else {
			isAutojoining = false
			isAutojoined = true
			return
		}

		isAutojoining = true
		channelsToAutojoin = channels
		startAutojoinTimer()
	}
}
