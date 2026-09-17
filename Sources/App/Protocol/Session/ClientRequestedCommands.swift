// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

final class ClientRequestedCommands {
	private enum Command {
		case ison
		case who
	}

	private struct Request {
		let command: Command
		let responseIsHidden: Bool
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
		requests.append(Request(command: .ison, responseIsHidden: true, nicknames: nicknames))
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

	var visibleWhoRequest: Bool {
		responseIsVisible(for: .who)
	}

	func recordWhoRequestOpened() {
		addRequest(for: .who, responseIsHidden: true)
	}

	func recordWhoRequestOpenedAsVisible() {
		addRequest(for: .who, responseIsHidden: false)
	}

	func recordWhoRequestClosed() {
		removeFirstRequest(for: .who)
	}

	private func addRequest(for command: Command, responseIsHidden: Bool) {
		requests.append(Request(command: command, responseIsHidden: responseIsHidden))
	}

	@discardableResult
	private func removeFirstRequest(for command: Command) -> Request? {
		guard let index = requests.firstIndex(where: { $0.command == command }) else {
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
