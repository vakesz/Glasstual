/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2011, Tony Million.
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 * list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
import Network

/// Path-change evaluator used by `Reachability` and tests.
/// Seeds from the first path without notifying; later changes fire reachable/unreachable.
enum ReachabilityPathEvent: Int {
	case none = 0
	case becameReachable = 1
	case becameUnreachable = 2
}

@objc(OELReachability)
public final nonisolated class Reachability: NSObject, @unchecked Sendable {
	@objc public var reachableBlock: ((Reachability) -> Void)?
	@objc public var unreachableBlock: ((Reachability) -> Void)?

	private var monitor: NWPathMonitor?
	private let monitorQueue = DispatchQueue(label: "com.vakesz.glasstual.reachability")
	private var currentlyReachable = false
	private var receivedInitialPath = false

	@objc(isReachable)
	public var reachable: Bool {
		currentlyReachable
	}

	@objc(reachabilityForInternetConnection)
	public static func reachabilityForInternetConnection() -> Reachability {
		Reachability()
	}

	deinit {
		stopNotifier()

		reachableBlock = nil
		unreachableBlock = nil
	}

	@objc
	@discardableResult
	public func startNotifier() -> Bool {
		/* A path monitor is single use: once cancelled it never delivers
		 another update. Create a fresh one for every start. */
		monitor?.cancel()

		let monitor = NWPathMonitor()
		self.monitor = monitor

		/* `receivedInitialPath` is deliberately seeded only once per object lifetime.
		 Resetting it here made every restart — the notifier is stopped on sleep and
		 started again on wake — discard the first update, so a connectivity change
		 across the sleep was never reported. */

		monitor.pathUpdateHandler = { [weak self] path in
			let reachable = path.status == .satisfied

			DispatchQueue.main.async {
				self?.pathChanged(reachable: reachable)
			}
		}

		monitor.start(queue: monitorQueue)

		return true
	}

	@objc
	public func stopNotifier() {
		monitor?.cancel()
		monitor = nil
	}

	private func pathChanged(reachable: Bool) {
		let event = Self.evaluatePathChange(
			reachable: reachable,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		switch event {
		case .none:
			break
		case .becameReachable:
			reachableBlock?(self)
		case .becameUnreachable:
			unreachableBlock?(self)
		}
	}

	@objc(evaluatePathChange:currentlyReachable:receivedInitialPath:)
	public static func evaluatePathChange(
		reachable: Bool,
		currentlyReachable: UnsafeMutablePointer<ObjCBool>,
		receivedInitialPath: UnsafeMutablePointer<ObjCBool>
	) -> Int {
		var currently = currentlyReachable.pointee.boolValue
		var received = receivedInitialPath.pointee.boolValue

		let event = evaluatePathChange(
			reachable: reachable,
			currentlyReachable: &currently,
			receivedInitialPath: &received
		)

		currentlyReachable.pointee = ObjCBool(currently)
		receivedInitialPath.pointee = ObjCBool(received)

		return event.rawValue
	}

	static func evaluatePathChange(
		reachable: Bool,
		currentlyReachable: inout Bool,
		receivedInitialPath: inout Bool
	) -> ReachabilityPathEvent {
		let wasReachable = currentlyReachable

		currentlyReachable = reachable

		/* The first path update describes the state at launch rather
		 than a change. Seed our state from it without notifying. */
		if receivedInitialPath == false {
			receivedInitialPath = true

			return .none
		}

		if reachable == wasReachable {
			return .none
		}

		return reachable ? .becameReachable : .becameUnreachable
	}
}
