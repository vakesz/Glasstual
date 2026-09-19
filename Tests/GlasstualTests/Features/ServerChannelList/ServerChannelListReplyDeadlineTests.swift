// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Channel-list reply deadline", .timeLimit(.minutes(1)))
struct ServerChannelListReplyDeadlineTests {
	@Test("A burst of replies advances one watchdog without shortening the last reply's timeout")
	func streamingExtendsOnePendingWatchdog() async {
		let clock = ReplyClock()
		let session = TestServerSession()
		session.markAsLoggedIn()
		let list = ServerChannelList(session: session, replyTimeout: 60, clock: clock.timerClock)
		defer {
			list.close()
			clock.finish()
		}
		var waits = clock.waits.makeAsyncIterator()
		list.beginRefresh()
		#expect(await waits.next() == 60)
		clock.advance(by: 40)
		for index in 0 ..< 1000 {
			list.addChannel("#channel\(index)", count: 1, topic: nil)
		}
		clock.advance(by: 20)
		#expect(await waits.next() == 40)
		#expect(list.model.isRefreshing)
		clock.advance(by: 39)
		#expect(list.model.isRefreshing)
		clock.advance(by: 1)
		for await refreshing in Observations({ list.model.isRefreshing }) where refreshing == false {
			break
		}
		for await filtering in Observations({ list.model.isFiltering }) where filtering == false {
			break
		}
		#expect(list.model.rows.count == 1000)
	}

	@Test("Closing a list cancels its pending deadline")
	func closeCancelsDeadline() async {
		let clock = ReplyClock()
		let session = TestServerSession()
		session.markAsLoggedIn()
		let list = ServerChannelList(session: session, replyTimeout: 60, clock: clock.timerClock)
		defer { clock.finish() }
		var waits = clock.waits.makeAsyncIterator()
		list.beginRefresh()
		#expect(await waits.next() == 60)
		list.addChannel("#discarded", count: 1, topic: nil)
		list.close()
		clock.advance(by: 60)
		#expect(list.model.rows.isEmpty)
		#expect(list.model.isFiltering == false)
	}
}

@MainActor
private final class ReplyClock {
	private struct Sleeper {
		let deadline: ContinuousClock.Instant
		let continuation: CheckedContinuation<Void, Never>
	}

	private var instant = ContinuousClock.now
	private var sleepers: [Sleeper] = []
	let waits: AsyncStream<TimeInterval>
	private let events: AsyncStream<TimeInterval>.Continuation

	init() {
		(waits, events) = AsyncStream.makeStream()
	}

	var timerClock: TimerClock {
		TimerClock(now: { self.instant }, wait: { interval in
			guard Task.isCancelled == false else { return }
			await withCheckedContinuation { continuation in
				self.sleepers.append(Sleeper(deadline: self.instant.advanced(by: .seconds(interval)), continuation: continuation))
				self.events.yield(interval)
			}
		})
	}

	func advance(by interval: TimeInterval) {
		instant = instant.advanced(by: .seconds(interval))
		let due = sleepers.filter { $0.deadline <= instant }
		sleepers.removeAll { $0.deadline <= instant }
		for sleeper in due {
			sleeper.continuation.resume()
		}
	}

	func finish() {
		let remaining = sleepers
		sleepers.removeAll()
		for sleeper in remaining {
			sleeper.continuation.resume()
		}
		events.finish()
	}
}
