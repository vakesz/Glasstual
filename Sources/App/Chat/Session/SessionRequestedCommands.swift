// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

final class SessionRequestedCommands {
	private enum Command {
		case ison
		case who
	}

	private struct Request {
		let command: Command
		let responseIsHidden: Bool
		/// The casefolded WHO mask. A `315` names this mask, so it is the only
		/// safe way to select its request when several WHOs are in flight.
		let target: String?
		/// A periodic WHO sweep can be superseded after a full interval; an
		/// initial WHO must remain open for its delayed first reply instead.
		let sentAt: Date?
		let expiresWithNextSweep: Bool
		/// The nicknames an ISON asked about. One reply answers for these and
		/// nobody else.
		var nicknames: [String] = []
	}

	private var requests: [Request] = []

	func removeCommands() {
		requests.removeAll()
	}

	var visibleIsonRequest: Bool {
		responseIsVisible(for: .ison)
	}

	/// Records a hidden ISON asking about `nicknames`.
	func recordIsonRequestOpened(askingAbout nicknames: [String]) {
		addRequest(for: .ison, responseIsHidden: true, nicknames: nicknames)
	}

	func recordIsonRequestOpenedAsVisible() {
		addRequest(for: .ison, responseIsHidden: false)
	}

	/** Closes the oldest ISON request and returns the nicknames it asked about.

	 A long list goes out as several ISON commands and each draws its own
	 `RPL_ISON`, so a reply says who is online among that one command's
	 nicknames. Read as the whole online set it signed off everyone the other
	 commands asked about, on every poll. Empty when no request was open. */
	@discardableResult
	func recordIsonRequestClosed() -> [String] {
		removeFirstRequest(for: .ison)?.nicknames ?? []
	}

	/// Whether an ISON is still waiting for its reply.
	var hasOpenIsonRequest: Bool {
		requests.contains { $0.command == .ison }
	}

	/// Polling ISON requests are one sweep, rather than an unbounded FIFO: a
	/// missing reply makes later replies impossible to correlate safely.
	var hasOpenHiddenIsonRequest: Bool {
		requests.contains { $0.command == .ison && $0.responseIsHidden }
	}

	/// Expires one incomplete hidden sweep before the next one begins.
	func discardHiddenIsonRequests() {
		requests.removeAll { $0.command == .ison && $0.responseIsHidden }
	}

	var visibleWhoRequest: Bool {
		responseIsVisible(for: .who)
	}

	func visibleWhoRequest(for target: String) -> Bool {
		requests.first(where: { $0.command == .who && $0.target == target })?.responseIsHidden == false
	}

	func recordWhoRequestOpened() {
		addRequest(for: .who, responseIsHidden: true)
	}

	func recordWhoRequestOpenedAsVisible() {
		addRequest(for: .who, responseIsHidden: false)
	}

	func recordWhoRequestOpened(for target: String, sentAt: Date = .now, expiresWithNextSweep: Bool = false) {
		addRequest(
			for: .who,
			responseIsHidden: true,
			target: target,
			sentAt: sentAt,
			expiresWithNextSweep: expiresWithNextSweep
		)
	}

	func recordWhoRequestOpenedAsVisible(for target: String) {
		addRequest(for: .who, responseIsHidden: false, target: target)
	}

	@discardableResult
	func recordWhoRequestClosed() -> Bool? {
		removeFirstRequest(for: .who)?.responseIsHidden
	}

	/** Closes the request whose mask `315` identified.

	 `nil` means no request has that target. `false` means it was a visible
	 command, which its caller presents in the hidden-responses console. */
	@discardableResult
	func recordWhoRequestClosed(for target: String) -> Bool? {
		removeFirstRequest { $0.command == .who && $0.target == target }?.responseIsHidden
	}

	/// Whether a hidden WHO is still waiting for its reply.
	///
	/// Unlike an ISON command, a WHO sweep takes one request per channel, so
	/// a sweep in flight legitimately holds several at once. A request that
	/// is still open after a full timer tick is one whose reply never came.
	var hasOpenHiddenWhoRequest: Bool {
		requests.contains { $0.command == .who && $0.responseIsHidden }
	}

	/// Expires only a periodic sweep old enough to have missed a full interval.
	/// Initial and visible WHO commands remain for their actual terminators.
	func discardExpiredHiddenWhoSweepRequests(now: Date, after interval: TimeInterval) {
		requests.removeAll {
			$0.command == .who && $0.responseIsHidden && $0.expiresWithNextSweep
				&& $0.sentAt.map { now.timeIntervalSince($0) >= interval } == true
		}
	}

	private func addRequest(
		for command: Command,
		responseIsHidden: Bool,
		nicknames: [String] = [],
		target: String? = nil,
		sentAt: Date? = nil,
		expiresWithNextSweep: Bool = false
	) {
		requests.append(
			Request(
				command: command,
				responseIsHidden: responseIsHidden,
				target: target,
				sentAt: sentAt,
				expiresWithNextSweep: expiresWithNextSweep,
				nicknames: nicknames
			)
		)
	}

	@discardableResult
	private func removeFirstRequest(for command: Command) -> Request? {
		removeFirstRequest { $0.command == command }
	}

	private func removeFirstRequest(matching predicate: (Request) -> Bool) -> Request? {
		guard let index = requests.firstIndex(where: predicate) else {
			return nil
		}

		return requests.remove(at: index)
	}

	private func responseIsVisible(for command: Command) -> Bool {
		guard let request = requests.first(where: { $0.command == command }) else {
			return false
		}

		return request.responseIsHidden == false
	}
}

/// The "Hidden Responses" window, where a reply this session asked for
/// without showing the command is printed instead of being dropped.
@MainActor
extension ServerSession {
	func removeRequestedCommands() {
		requestedCommands.removeCommands()
	}

	func createHiddenCommandResponses() {
		guard !isTerminating, hiddenCommandResponsesConsole == nil,
		      let console = findConversationOrCreate("Hidden Responses", isConsole: true)
		else { return }

		hiddenCommandResponsesConsole = console
		output?.select(console)
		printDebugInformation(String(localized: .IRC.commandResponsesWhichAreNormallyHidden), in: console)
	}

	func printReplyToHiddenCommandResponsesConsole(_ message: Message) {
		guard let console = hiddenCommandResponsesConsole else { return }
		printReply(message, in: console)
	}
}
