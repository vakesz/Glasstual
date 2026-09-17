// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

final class TimedCommand {
	private static var lastIdentifier = 0

	let identifier: String
	let clientId: String
	let channelId: String?
	let command: String

	/// The timer the command runs on. Callers read its interval, iteration and
	/// activity off it directly.
	private(set) var timer: ClientTimer!

	init(command: String, onClient client: Client, inChannel channel: Channel? = nil) {
		identifier = Self.nextIdentifier()
		clientId = client.uniqueIdentifier
		channelId = channel?.uniqueIdentifier
		self.command = command

		timer = ClientTimer { [weak self, weak client] _ in
			guard let self, let client else {
				return
			}

			client.onTimedCommand(self)
		}
	}

	isolated deinit {
		timer.stop()
	}

	func start(_ interval: TimeInterval, onRepeat repeatTimer: Bool = false, iterations: UInt = 0) {
		timer.start(interval, repeats: repeatTimer, iterations: iterations)
	}

	func stop() {
		timer.stop()
	}

	/// Runs the command's last interval again, or reports that it never ran
	/// one: the timer's interval is zero until the first `start`.
	func restart() -> Bool {
		guard timer.interval > 0 else {
			return false
		}

		start(timer.interval, onRepeat: timer.repeats, iterations: timer.iterations)

		return true
	}

	private static func nextIdentifier() -> String {
		lastIdentifier += 1
		return String(lastIdentifier)
	}
}
