// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Darwin
import Foundation
import os

private let scriptExecutionLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "UserScriptRunner"
)
private nonisolated let appleScriptSuite = AEEventClass(0x6173_6372)
private nonisolated let appleScriptSubroutineEvent = AEEventID(0x7073_6272)
private nonisolated let appleScriptSubroutineName = AEKeyword(0x736E_616D)

/// Runs the `glasstualcmd` script bridge, kept free of `ServerSession` so it can be
/// exercised without a live session.
enum UserScriptRunner {
	nonisolated enum OutputError: LocalizedError, Equatable {
		case tooLarge
		case invalidUTF8

		var errorDescription: String? {
			switch self {
			case .tooLarge: String(localized: .Scripts.scriptOutputTooLarge)
			case .invalidUTF8: String(localized: .Scripts.scriptOutputInvalidEncoding)
			}
		}
	}

	/// The handler name Glasstual asks a script to run.
	nonisolated static let handlerName = "glasstualcmd"

	/// `errOSAGeneralError`: what a failure that reports no error number is
	/// recorded as.
	nonisolated static let unknownScriptError = -2700

	/** How much of a script's output is kept.

	 Everything past it is read and dropped: the pipe still has to be drained so
	 the script can finish, but a runaway script must not grow the buffer
	 without bound. The same ceiling bounds the decoded text and the result a
	 script hands back, because an AppleScript result never passes through the
	 reader at all. */
	nonisolated static let maximumOutputBytes = 1 << 20

	/** Reads `handle` to end of file, keeping at most ``maximumOutputBytes``.

	 This runs while the script is still executing. A pipe holds a fixed amount
	 (64 KB on macOS); a script that writes more blocks in `write(2)` until
	 something reads, so a reader that waits for termination first would wedge
	 the script and never start.

	 Readiness notifications only wake this task. The descriptor is nonblocking,
	 so a silent script neither occupies a cooperative-pool thread nor prevents
	 another script's output from being read. The caller owns the open handle
	 until this method returns and must not read it concurrently. */
	@concurrent
	static func readOutput(from handle: FileHandle) async throws -> Data {
		try Task.checkCancellation()
		let descriptor = handle.fileDescriptor
		let flags = fcntl(descriptor, F_GETFL)
		guard flags != -1 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
		guard flags & O_ACCMODE != O_WRONLY else { throw POSIXError(.EBADF) }
		guard fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
		let (readiness, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
		handle.readabilityHandler = { _ in continuation.yield(()) }
		defer {
			handle.readabilityHandler = nil
			continuation.finish()
			_ = fcntl(descriptor, F_SETFL, flags)
		}
		continuation.yield(())
		var accumulated = Data()
		var exceededLimit = false
		var buffer = [UInt8](repeating: 0, count: 64 * 1024)
		for await _ in readiness {
			while true {
				try Task.checkCancellation()
				let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
				if count == 0 {
					guard exceededLimit == false else { throw OutputError.tooLarge }
					return accumulated
				}
				if count < 0 {
					let error = errno
					if error == EINTR {
						continue
					}
					if error == EAGAIN || error == EWOULDBLOCK {
						break
					}
					throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
				}
				let kept = min(count, maximumOutputBytes - accumulated.count)
				accumulated.append(contentsOf: buffer.prefix(kept))
				exceededLimit = exceededLimit || kept < count
			}
		}
		throw CancellationError()
	}

	/// Runs the executable at `url` with `arguments` and returns what it wrote
	/// to standard output, read while it runs. `NSUserUnixTask` has no process
	/// termination API: cancellation discards its result after execution ends,
	/// while the reader keeps draining so the script can finish writing.
	@concurrent
	static func runUnixScript(at url: URL, arguments: [String]) async throws -> Data {
		try Task.checkCancellation()
		let task = try NSUserUnixTask(url: url)
		let pipe = Pipe()
		let readHandle = pipe.fileHandleForReading
		let writeHandle = pipe.fileHandleForWriting
		task.standardOutput = writeHandle
		defer {
			try? readHandle.close()
			try? writeHandle.close()
		}

		// Start draining before the script runs. Reading only once it has
		// terminated deadlocks a script whose output overflows the pipe. This
		// task deliberately outlives caller cancellation: the Foundation task
		// keeps executing, so cancelling an async-let reader would strand it in
		// write(2). This scope joins the reader before closing its handle.
		let output = Task { try await readOutput(from: readHandle) }
		defer { output.cancel() }
		let executionError: (any Error)?
		do {
			try await task.execute(withArguments: arguments)
			executionError = nil
		} catch {
			executionError = error
		}

		// The task holds the only other reference to the write end; closing it
		// here is what lets the drain above see EOF.
		try? writeHandle.close()
		let outputResult = await output.result
		try Task.checkCancellation()
		let data = try outputResult.get()

		if let executionError {
			throw executionError
		}

		return data
	}

	/// Runs `handler` in the user AppleScript at `url` and returns its result
	/// as text, when it has one.
	@concurrent
	static func runUserAppleScript(at url: URL, handler: String, input: String, target: String?) async throws -> String? {
		let task = try NSUserAppleScriptTask(url: url)
		let result = try await task.execute(withAppleEvent: appleEvent(handler: handler, input: input, target: target))

		return result.stringValue
	}

	nonisolated static func decodedOutput(_ data: Data) throws -> String { // nonisolated: pure
		guard data.count <= maximumOutputBytes else { throw OutputError.tooLarge }
		guard let output = String(data: data, encoding: .utf8) else { throw OutputError.invalidUTF8 }
		return output
	}

	nonisolated static func appleEvent( // nonisolated: pure
		handler: String,
		input: String,
		target: String?
	) -> NSAppleEventDescriptor {
		let parameters = NSAppleEventDescriptor.list()
		parameters.insert(NSAppleEventDescriptor(string: input), at: 1)
		parameters.insert(NSAppleEventDescriptor(string: target ?? ""), at: 2)
		let event = NSAppleEventDescriptor(
			eventClass: appleScriptSuite,
			eventID: appleScriptSubroutineEvent,
			targetDescriptor: NSAppleEventDescriptor(processIdentifier: getpid()),
			returnID: AEReturnID(kAutoGenerateReturnID),
			transactionID: AETransactionID(kAnyTransactionID)
		)
		event.setParam(NSAppleEventDescriptor(string: handler), forKeyword: appleScriptSubroutineName)
		event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))
		return event
	}

	/// Turns the `NSDictionary` that `NSAppleScript` reports failures through
	/// into an `Error` the shared reporting path understands.
	static func error(from information: NSDictionary?) -> NSError {
		let userInfo = (information as? [String: Any]) ?? [:]
		let code = (userInfo[NSAppleScript.errorNumber] as? Int) ?? unknownScriptError
		return NSError(domain: NSOSStatusErrorDomain, code: code, userInfo: userInfo)
	}
}
