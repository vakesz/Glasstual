/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

@objc(TLOTimer)
final nonisolated class TimerImplementation: NSObject, @unchecked Sendable {
	private final class ActionBox: @unchecked Sendable {
		let action: (AnyObject) -> Void

		init(action: @escaping (AnyObject) -> Void) {
			self.action = action
		}
	}

	private let action: ActionBox
	@objc var actionBlock: (AnyObject) -> Void {
		action.action
	}

	@objc var queue: DispatchQueue?
	@objc var context: AnyObject?
	@objc private(set) var startTime: TimeInterval = 0
	@objc private(set) var interval: TimeInterval = 0
	@objc private(set) var repeatTimer = false
	@objc private(set) var iterations: UInt = 0
	@objc private(set) var currentIteration: UInt = 0
	private var timerSource: DispatchSourceTimer?

	@available(*, unavailable, message: "Use init(actionBlock:on:) instead")
	override init() {
		fatalError("Unavailable")
	}

	@objc(timerWithActionBlock:)
	static func timer(actionBlock: @escaping (AnyObject) -> Void) -> TimerImplementation {
		TimerImplementation(actionBlock: actionBlock, on: nil)
	}

	@objc(timerWithActionBlock:onQueue:)
	static func timer(
		actionBlock: @escaping (AnyObject) -> Void,
		onQueue queue: DispatchQueue?
	) -> TimerImplementation {
		TimerImplementation(actionBlock: actionBlock, on: queue)
	}

	@objc(initWithActionBlock:)
	convenience init(actionBlock: @escaping (AnyObject) -> Void) {
		self.init(actionBlock: actionBlock, on: nil)
	}

	@objc(initWithActionBlock:onQueue:)
	init(actionBlock: @escaping (AnyObject) -> Void, on queue: DispatchQueue?) {
		action = ActionBox(action: actionBlock)
		self.queue = queue
		super.init()
	}

	deinit {
		stop()
	}

	@objc var timerIsActive: Bool {
		timerSource != nil
	}

	@objc var timeRemaining: TimeInterval {
		interval - (CFAbsoluteTimeGetCurrent() - startTime)
	}

	@objc(start:)
	func start(_ timerInterval: TimeInterval) {
		start(timerInterval, onRepeat: false, iterations: 0)
	}

	@objc(start:onRepeat:)
	func start(_ timerInterval: TimeInterval, onRepeat repeatTimer: Bool) {
		start(timerInterval, onRepeat: repeatTimer, iterations: 0)
	}

	@objc(start:onRepeat:iterations:)
	func start(_ timerInterval: TimeInterval, onRepeat repeatTimer: Bool, iterations: UInt) {
		precondition(timerInterval > 0)
		stop()

		let timer = DispatchSource.makeTimerSource(queue: queue ?? .main)
		if repeatTimer {
			timer.schedule(deadline: .now() + timerInterval, repeating: timerInterval)
		} else {
			timer.schedule(deadline: .now() + timerInterval)
		}
		timer.setEventHandler { [weak self] in self?.fire() }

		interval = timerInterval
		self.repeatTimer = repeatTimer
		self.iterations = iterations
		currentIteration = 0
		timerSource = timer
		startTime = CFAbsoluteTimeGetCurrent()
		timer.resume()
	}

	@objc func stop() {
		timerSource?.cancel()
		timerSource = nil
	}

	private func fire() {
		if currentIteration < UInt.max {
			currentIteration += 1
		}
		if !repeatTimer || (iterations > 0 && iterations == currentIteration) {
			stop()
		}
		action.action(self)
	}
}
