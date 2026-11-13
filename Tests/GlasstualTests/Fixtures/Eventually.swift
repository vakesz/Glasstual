// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Testing

/** Waits for state the code under test reaches on its own.

 ``until(timeout:_:)`` polls a condition, yielding first so work already queued
 runs before any real time passes, then sleeping briefly. ``withDeadline(_:onExpiry:perform:)``
 runs a body that waits on a stream and finishes that stream if the deadline
 passes, so a missed signal fails the test instead of hanging it. */
@MainActor
enum Eventually {
	struct TimedOut: Error, CustomStringConvertible {
		let description: String
	}

	static func until(
		timeout: Duration = .seconds(5),
		_ description: @autoclosure () -> String = "condition",
		sourceLocation: SourceLocation = #_sourceLocation,
		_ condition: @MainActor () -> Bool
	) async throws {
		let deadline = ContinuousClock.now + timeout
		var yields = 0
		while !condition() {
			guard ContinuousClock.now < deadline else {
				let message = "Timed out waiting for \(description())"
				Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
				throw TimedOut(description: message)
			}
			if yields < 100 {
				yields += 1
				await Task.yield()
			} else {
				try await Task.sleep(for: .milliseconds(10))
			}
		}
	}

	/// ``until(timeout:_:sourceLocation:_:)`` for a condition that has to await
	/// something, such as a read from an actor, to find out.
	static func untilResolved(
		timeout: Duration = .seconds(5),
		_ description: @autoclosure () -> String = "condition",
		sourceLocation: SourceLocation = #_sourceLocation,
		_ condition: @MainActor () async -> Bool
	) async throws {
		let deadline = ContinuousClock.now + timeout
		var yields = 0
		while await !condition() {
			guard ContinuousClock.now < deadline else {
				let message = "Timed out waiting for \(description())"
				Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
				throw TimedOut(description: message)
			}
			if yields < 100 {
				yields += 1
				await Task.yield()
			} else {
				try await Task.sleep(for: .milliseconds(10))
			}
		}
	}

	/// ``withDeadline(_:onExpiry:perform:)`` for a body that must not run on the
	/// main actor, such as a `@concurrent` test driving the connection host. The
	/// body stays where the caller is; only the deadline task is separate, so
	/// `onExpiry` has to be safe to call from anywhere.
	nonisolated static func withUnisolatedDeadline<Result>( // nonisolated: pure
		_ timeout: Duration = .seconds(5),
		onExpiry: @escaping @Sendable () -> Void,
		perform body: () async throws -> Result
	) async rethrows -> Result {
		let deadline = Task {
			try? await Task.sleep(for: timeout)
			guard !Task.isCancelled else { return }
			onExpiry()
		}
		defer { deadline.cancel() }
		return try await body()
	}

	/// Runs `body` with `onExpiry` called once `timeout` has passed. The
	/// deadline task is cancelled when the body returns or throws.
	static func withDeadline<Result>(
		_ timeout: Duration = .seconds(5),
		onExpiry: @escaping @MainActor () -> Void,
		perform body: () async throws -> Result
	) async rethrows -> Result {
		let deadline = Task {
			try? await Task.sleep(for: timeout)
			guard !Task.isCancelled else { return }
			onExpiry()
		}
		defer { deadline.cancel() }
		return try await body()
	}
}
