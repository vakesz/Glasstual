// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension ServerSession {
	/// Keeps a pending user decision in this session. A delayed answer cannot
	/// act on a replacement connection, a removed conversation or a cancelled
	/// task.
	func requestConfirmation(
		_ request: AlertRequest,
		isCurrent: @escaping @MainActor (ServerSession) -> Bool = { _ in true },
		perform action: @escaping @MainActor (ServerSession) -> Void
	) {
		guard let output else {
			if !isTerminating, isCurrent(self) {
				action(self)
			}
			return
		}
		let identifier = UUID()
		let startupIdentifier = startup.identifier
		let connection = socket?.uniqueIdentifier
		scheduled.confirmations[identifier] = Task { [weak self, weak output] in
			guard let output else {
				self?.scheduled.confirmations.removeValue(forKey: identifier)
				return
			}
			let accepted = await output.confirm(request)
			guard let self else { return }
			defer { scheduled.confirmations.removeValue(forKey: identifier) }
			guard accepted, !Task.isCancelled, !isTerminating,
			      startup.identifier == startupIdentifier, socket?.uniqueIdentifier == connection,
			      isCurrent(self) else { return }
			action(self)
		}
	}

	/** Asks a question whose answer is the button, not a yes or a no, and keeps
	 the pending answer in this session as ``requestConfirmation(_:isCurrent:perform:)``
	 does. `answer` is called with ``AlertResponse/default`` when there is no
	 window to ask in, so a question whose safe answer is the default button is
	 never answered by the absence of someone to ask. */
	func requestResponse(
		_ request: AlertRequest,
		isCurrent: @escaping @MainActor (ServerSession) -> Bool = { _ in true },
		answer: @escaping @MainActor (ServerSession, AlertResponse) -> Void
	) {
		guard let output else {
			if !isTerminating, isCurrent(self) {
				answer(self, .default)
			}
			return
		}
		let identifier = UUID()
		let startupIdentifier = startup.identifier
		let connection = socket?.uniqueIdentifier
		scheduled.confirmations[identifier] = Task { [weak self, weak output] in
			guard let output else {
				self?.scheduled.confirmations.removeValue(forKey: identifier)
				return
			}
			let response = await output.respond(to: request)
			guard let self else { return }
			defer { scheduled.confirmations.removeValue(forKey: identifier) }
			guard !Task.isCancelled, !isTerminating,
			      startup.identifier == startupIdentifier, socket?.uniqueIdentifier == connection,
			      isCurrent(self) else { return }
			answer(self, response)
		}
	}
}
