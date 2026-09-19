// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Where a file-log operation is carried out.

 A value holding one closure rather than a protocol: the only thing that varies
 is which actor is behind it, and the one production actor is
 ``FileLogSink``. */
nonisolated struct FileLogSinkPort: Sendable {
	let process: @Sendable (FileLogOperation) async -> FileLogResult

	/// The real transcript files on disk.
	static func fileSystem() -> Self {
		let sink = FileLogSink()

		return Self { await sink.process($0) }
	}
}

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
	func flush() async -> Bool {
		guard !finished else { return false }
		return await withCheckedContinuation { barrier in
			continuation.yield(Command(operation: .flush, completion: { barrier.resume(returning: $0) }))
		}
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
