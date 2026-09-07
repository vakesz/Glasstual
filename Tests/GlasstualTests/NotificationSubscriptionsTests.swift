/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Notification subscription ownership", .timeLimit(.minutes(1)))
struct NotificationSubscriptionsTests {
	@Test("Registration is ready for a burst posted before the consumer task starts")
	func registrationIsReadyImmediately() async {
		let center = NotificationCenter()
		let name = Notification.Name("burst-test")
		let subscriptions = NotificationSubscriptions()
		let (delivered, continuation) = AsyncStream<Int>.makeStream()
		subscriptions.observe(name, center: center) { notification in
			continuation.yield(notification.userInfo?["index"] as? Int ?? -1)
		}
		for index in 0 ..< 5 {
			center.post(name: name, object: nil, userInfo: ["index": index])
		}
		var values: [Int] = []
		for await value in delivered {
			values.append(value)
			if values.count == 5 {
				break
			}
		}
		#expect(values == [0, 1, 2, 3, 4])
		subscriptions.cancelAll()
	}

	@Test("Release removes synchronous observers without changing inline delivery")
	func releaseCancelsSynchronousObserver() {
		let center = NotificationCenter()
		var subscriptions: NotificationSubscriptions? = NotificationSubscriptions()
		var count = 0
		subscriptions?.observeSynchronously(ReleaseProbeMessage.self, center: center) {
			MainActor.preconditionIsolated()
			count += 1
		}
		center.post(name: ReleaseProbeMessage.name, object: nil)
		#expect(count == 1)
		subscriptions = nil
		center.post(name: ReleaseProbeMessage.name, object: nil)
		#expect(count == 1)
	}

	@Test("Release cancels the consumer and releases its captured state")
	func releaseCancelsAsyncConsumer() async {
		let (released, continuation) = AsyncStream<Void>.makeStream()
		var lifetime: NotificationHandlerLifetime? = NotificationHandlerLifetime(released: continuation)
		var subscriptions: NotificationSubscriptions? = NotificationSubscriptions()
		subscriptions?.observe(Notification.Name("release-test-\(UUID().uuidString)")) { [lifetime] _ in
			_ = lifetime
		}
		lifetime = nil
		subscriptions = nil
		var iterator = released.makeAsyncIterator()
		#expect(await iterator.next() != nil)
	}

	@Test("Object filtering is preserved and cancellation discards pending delivery")
	func objectFilterAndPendingCancellation() async {
		let center = NotificationCenter()
		let name = Notification.Name("filter-test")
		let selectedObject = NSObject()
		let otherObject = NSObject()
		let subscriptions = NotificationSubscriptions()
		let (delivered, continuation) = AsyncStream<Void>.makeStream()
		var count = 0
		subscriptions.observe(name, object: selectedObject, center: center) { _ in
			count += 1
			continuation.yield(())
		}
		center.post(name: name, object: otherObject)
		center.post(name: name, object: selectedObject)
		for await _ in delivered {
			break
		}
		#expect(count == 1)

		center.post(name: name, object: selectedObject)
		subscriptions.cancelAll()
		let (barrier, barrierContinuation) = AsyncStream<Void>.makeStream()
		subscriptions.observe(name, center: center) { _ in barrierContinuation.yield(()) }
		center.post(name: name, object: selectedObject)
		for await _ in barrier {
			break
		}
		#expect(count == 1)
		subscriptions.cancelAll()
	}
}

private struct ReleaseProbeMessage: NotificationCenter.MainActorMessage {
	typealias Subject = NSObject
	static let name = Notification.Name("release-synchronous-test")

	static func makeMessage(_: Notification) -> Self? {
		Self()
	}
}

@MainActor
private final class NotificationHandlerLifetime {
	private let released: AsyncStream<Void>.Continuation

	init(released: AsyncStream<Void>.Continuation) {
		self.released = released
	}

	isolated deinit {
		released.yield(())
		released.finish()
	}
}
