// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// One consumer, not one Task per write. Awaiting even a reentrant test sink
/// cannot let the next command overtake the current one.
@MainActor
final class FileLogCommands {
	private struct Command: Sendable {
		let operation: FileLogOperation
		var completion: (@MainActor @Sendable (Bool) -> Void)?
	}

	private let continuation: AsyncStream<Command>.Continuation
	private var idleSweep: SessionTimer?
	private var finished = false
	private var flushWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

	/// `reportNoSpace` is how the disk filling up is told to whoever presents it;
	/// a stream built without one simply drops the lines it cannot write.
	init(
		sink: FileLogSinkPort = .fileSystem(),
		reportNoSpace: @escaping @MainActor @Sendable () -> Void = {}
	) {
		let (stream, continuation) = AsyncStream<Command>.makeStream()
		self.continuation = continuation
		Task {
			var succeeded = true
			for await command in stream {
				let result = await sink.process(command.operation)
				succeeded = succeeded && result.succeeded
				if result.outOfSpace {
					reportNoSpace()
				}
				command.completion?(succeeded)
				if case .shutdown = command.operation {
					return
				}
			}
			_ = await sink.process(.shutdown)
		}
		/* A transcript file left open holds a security-scoped lease on a folder
		 the user chose. The sweep closes the ones nothing has written to. */
		idleSweep = SessionTimer { [weak self] _ in
			self?.submit(.sweep(Date()))
		}
		idleSweep?.start(Self.idleSweepInterval, repeats: true)
	}

	/// How often open transcript files are checked for having gone idle.
	private static let idleSweepInterval: TimeInterval = 600

	isolated deinit {
		idleSweep?.stop()
		continuation.finish()
	}

	@discardableResult
	func submit(_ operation: FileLogOperation) -> Bool {
		guard !finished else { return false }
		if case .shutdown = operation {
			return false
		}
		continuation.yield(Command(operation: operation))
		return true
	}

	/// Reports all failures since this stream was created, not merely fsync errors.
	/// A cancelled caller or a stream that no longer takes commands answers `false`.
	func flush() async -> Bool {
		guard !finished, Task.isCancelled == false else { return false }
		let identifier = UUID()
		return await withTaskCancellationHandler {
			await withCheckedContinuation { barrier in
				flushWaiters[identifier] = barrier
				/* `onCancel` hops back to the main actor, so it can run before the
				 waiter is stored. Storing it first and then reading the
				 cancellation means one of the two always resumes it. */
				guard Task.isCancelled == false else {
					finishFlush(identifier, succeeded: false)
					return
				}
				let result = continuation.yield(Command(operation: .flush, completion: { [weak self] succeeded in
					self?.finishFlush(identifier, succeeded: succeeded)
				}))
				if case .terminated = result {
					finishFlush(identifier, succeeded: false)
				}
			}
		} onCancel: {
			Task { await self.finishFlush(identifier, succeeded: false) }
		}
	}

	/// Resumes a waiter once; whichever of the stream and a cancellation comes second finds nothing.
	private func finishFlush(_ identifier: UUID, succeeded: Bool) {
		flushWaiters.removeValue(forKey: identifier)?.resume(returning: succeeded)
	}

	func finish(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
		guard !finished else { completion(false); return }
		finished = true
		idleSweep?.stop()
		idleSweep = nil
		continuation.yield(Command(operation: .shutdown, completion: completion))
		continuation.finish()
	}
}
