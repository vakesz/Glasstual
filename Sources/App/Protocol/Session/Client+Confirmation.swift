// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension Client {
	/// Keeps a pending user decision in this session. A delayed answer cannot
	/// act on a replacement connection, a removed channel or a cancelled task.
	func requestConfirmation(
		_ request: AlertRequest,
		isCurrent: @escaping @MainActor (Client) -> Bool = { _ in true },
		perform action: @escaping @MainActor (Client) -> Void
	) {
		guard let output else {
			if !isTerminating, isCurrent(self) {
				action(self)
			}
			return
		}
		let identifier = UUID()
		let session = startup.identifier
		let connection = socket?.uniqueIdentifier
		pendingConfirmationTasks[identifier] = Task { [weak self, weak output] in
			guard let output else {
				self?.pendingConfirmationTasks.removeValue(forKey: identifier)
				return
			}
			let accepted = await output.confirm(request)
			guard let self else { return }
			defer { pendingConfirmationTasks.removeValue(forKey: identifier) }
			guard accepted, !Task.isCancelled, !isTerminating,
			      startup.identifier == session, socket?.uniqueIdentifier == connection,
			      isCurrent(self) else { return }
			action(self)
		}
	}
}
