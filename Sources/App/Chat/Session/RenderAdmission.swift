// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Counts submitted work until its transcript application completes. Network
/// readers wait here before admitting another wire line, carrying the host's
/// acknowledgement boundary through rendering and TextKit application.
@MainActor
final class RenderAdmission {
	private let capacity: Int
	private var pending: [UUID: String] = [:]
	private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

	init(capacity: Int = 256) {
		precondition(capacity > 0)
		self.capacity = capacity
	}

	var pendingCount: Int {
		pending.count
	}

	var hasCapacity: Bool {
		pending.count < capacity
	}

	var waitingProducerCount: Int {
		waiters.count
	}

	func submit(for view: String) -> UUID {
		let identifier = UUID()
		pending[identifier] = view
		return identifier
	}

	func finish(_ identifier: UUID) {
		pending.removeValue(forKey: identifier)
		resumeProducersIfReady()
	}

	func retire(view: String) {
		pending = pending.filter { $0.value != view }
		resumeProducersIfReady()
	}

	func waitForCapacity() async {
		let identifier = UUID()
		await withTaskCancellationHandler {
			while pending.count >= capacity, !Task.isCancelled {
				await withCheckedContinuation { waiters[identifier] = $0 }
			}
		} onCancel: {
			Task { @MainActor in self.waiters.removeValue(forKey: identifier)?.resume() }
		}
	}

	private func resumeProducersIfReady() {
		guard pending.count < capacity else { return }
		let ready = waiters.values
		waiters.removeAll()
		for waiter in ready {
			waiter.resume()
		}
	}
}

/// The send path's view of the budget above: the feature satisfies the
/// requirement the outbound layer declares, so nothing under `Chat/` or
/// `Protocol/` names a transcript type.
extension RenderAdmission: OutboundTextAdmission {}
