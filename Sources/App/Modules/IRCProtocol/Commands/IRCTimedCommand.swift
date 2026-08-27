/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_
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

@objc(IRCTimedCommand)
public final class TimedCommand: NSObject {
	private static let identifierLock = NSLock()
	private nonisolated(unsafe) static var lastIdentifier = 0

	@objc public let identifier: String
	@objc public let clientId: String
	@objc public let channelId: String?
	@objc public let command: String

	private var timer: TimerImplementation!
	private var startedBefore = false

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(command:onClient:inChannel:)")
	}

	@objc(initWithCommand:onClient:)
	public convenience init(command: String, onClient client: IRCClient) {
		self.init(command: command, onClient: client, inChannel: nil)
	}

	@objc(initWithCommand:onClient:inChannel:)
	public init(command: String, onClient client: IRCClient, inChannel channel: IRCChannel?) {
		identifier = Self.nextIdentifier()
		clientId = client.uniqueIdentifier
		channelId = channel?.uniqueIdentifier
		self.command = command

		super.init()

		timer = TimerImplementation(actionBlock: { [weak self, weak client] _ in
			guard let self, let client else {
				return
			}

			_ = client.perform(NSSelectorFromString("onTimedCommand:"), with: self)
		})
	}

	deinit {
		timer.stop()
	}

	@objc(start:)
	public func start(_ interval: TimeInterval) {
		start(interval, onRepeat: false, iterations: 0)
	}

	@objc(start:onRepeat:)
	public func start(_ interval: TimeInterval, onRepeat repeatTimer: Bool) {
		start(interval, onRepeat: repeatTimer, iterations: 0)
	}

	@objc(start:onRepeat:iterations:)
	public func start(_ interval: TimeInterval, onRepeat repeatTimer: Bool, iterations: UInt) {
		timer.start(interval, onRepeat: repeatTimer, iterations: iterations)
		startedBefore = true
	}

	@objc public func stop() {
		timer.stop()
	}

	@objc public func restart() -> Bool {
		guard startedBefore else {
			return false
		}

		start(timerInterval, onRepeat: repeatTimer, iterations: iterations)
		return true
	}

	@objc public var startTime: TimeInterval {
		timer.startTime
	}

	@objc public var timeRemaining: TimeInterval {
		timer.timeRemaining
	}

	@objc public var timerInterval: TimeInterval {
		timer.interval
	}

	@objc public var timerIsActive: Bool {
		timer.timerIsActive
	}

	@objc public var repeatTimer: Bool {
		timer.repeatTimer
	}

	@objc public var iterations: UInt {
		timer.iterations
	}

	@objc public var currentIteration: UInt {
		timer.currentIteration
	}

	private static func nextIdentifier() -> String {
		identifierLock.lock()
		defer { identifierLock.unlock() }

		lastIdentifier += 1
		return String(lastIdentifier)
	}
}
