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
