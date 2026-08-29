/* *********************************************************************
 *
 *           Copyright (c) 2020 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
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
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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

import CoreServices
import Foundation
import Synchronization

/// One file-system change reported by FSEvents.
public struct XRFileSystemEvent: Sendable, Hashable {
	public let url: URL
	public let flags: FSEventStreamEventFlags
	public let identifier: FSEventStreamEventId

	public init(url: URL, flags: FSEventStreamEventFlags, identifier: FSEventStreamEventId) {
		self.url = url
		self.flags = flags
		self.identifier = identifier
	}
}

/// Watches paths for file-system changes.
public enum XRFileSystemMonitor {
	/// Yields a batch of events every time FSEvents reports one, until the
	/// consuming task is cancelled or the stream is dropped.
	///
	/// `latency` is the coalescing window FSEvents applies before delivering.
	public static func events(
		for urls: [URL],
		latency: TimeInterval = 0
	) -> AsyncStream<[XRFileSystemEvent]> {
		precondition(urls.isEmpty == false)
		precondition(latency >= 0)

		let paths = urls.map(\.standardizedFileURL.path) as CFArray

		return AsyncStream { continuation in
			/* FSEvents takes a dispatch queue, and this one has to be serial:
			 teardown runs on it so that invalidating the stream cannot overlap
			 a callback already executing, which would leave that callback
			 reading a session the teardown has released. A concurrent queue
			 also gives up batch ordering, which a file monitor needs. This is
			 not a synchronisation domain for mutable state -- the session's
			 state is already in a `Mutex` -- so an actor cannot replace it. */
			let queue = DispatchQueue(label: "com.vakesz.glasstual.file-system-monitor")
			let session = FileSystemEventSession(continuation: continuation)

			guard session.start(paths: paths, latency: latency, queue: queue) else {
				continuation.finish()
				return
			}

			continuation.onTermination = { _ in
				/* Torn down on the stream's own queue. FSEvents may be running
				 the callback there right now, and stopping from anywhere else
				 would race the delivery already in flight. The session is held
				 by this closure, so it outlives the stream it owns. */
				queue.async {
					session.stop()
				}
			}
		}
	}

	/// Convenience for the common single-URL case.
	public static func events(
		for url: URL,
		latency: TimeInterval = 0
	) -> AsyncStream<[XRFileSystemEvent]> {
		events(for: [url], latency: latency)
	}
}

/// Owns one FSEvents stream and the continuation it feeds.
///
/// FSEvents hands the callback an untyped `info` pointer, which is this object;
/// the stream itself lives behind a lock so teardown can happen from the
/// termination handler.
private final class FileSystemEventSession: Sendable {
	private let continuation: AsyncStream<[XRFileSystemEvent]>.Continuation
	/** Stored as an address rather than an `FSEventStreamRef`, which is an opaque
	 pointer and so is not sendable. The stream is created once, used only on the
	 dispatch queue it was given, and destroyed once. */
	private let streamAddress = Mutex<UInt>(0)

	init(continuation: AsyncStream<[XRFileSystemEvent]>.Continuation) {
		self.continuation = continuation
	}

	func start(paths: CFArray, latency: TimeInterval, queue: DispatchQueue) -> Bool {
		var context = FSEventStreamContext(
			version: 0,
			info: Unmanaged.passUnretained(self).toOpaque(),
			retain: nil,
			release: nil,
			copyDescription: nil
		)
		let flags = FSEventStreamCreateFlags(
			kFSEventStreamCreateFlagFileEvents
				| kFSEventStreamCreateFlagNoDefer
				| kFSEventStreamCreateFlagUseCFTypes
		)

		guard let created = FSEventStreamCreate(
			nil,
			fileSystemMonitorCallback,
			&context,
			paths,
			FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
			latency,
			flags
		) else {
			return false
		}

		FSEventStreamSetDispatchQueue(created, queue)

		guard FSEventStreamStart(created) else {
			FSEventStreamInvalidate(created)
			FSEventStreamRelease(created)
			return false
		}

		adopt(created)
		return true
	}

	private func adopt(_ created: FSEventStreamRef) {
		let address = UInt(bitPattern: UnsafeRawPointer(created))
		streamAddress.withLock { $0 = address }
	}

	/// Stops and destroys the stream, once. Callers run this on the stream's own
	/// dispatch queue so it cannot race a delivery in flight.
	func stop() {
		let address = streamAddress.withLock { current -> UInt in
			let address = current
			current = 0
			return address
		}

		guard let pointer = UnsafeRawPointer(bitPattern: address) else {
			return
		}

		let stream = OpaquePointer(pointer)
		FSEventStreamStop(stream)
		FSEventStreamInvalidate(stream)
		FSEventStreamRelease(stream)
	}

	func receive(
		paths: NSArray,
		flags: UnsafePointer<FSEventStreamEventFlags>,
		identifiers: UnsafePointer<FSEventStreamEventId>,
		count: Int
	) {
		var events: [XRFileSystemEvent] = []
		events.reserveCapacity(count)

		for index in 0 ..< count {
			guard let path = paths[index] as? String else { continue }
			events.append(XRFileSystemEvent(
				url: URL(fileURLWithPath: path),
				flags: flags[index],
				identifier: identifiers[index]
			))
		}

		continuation.yield(events)
	}
}

private let fileSystemMonitorCallback: FSEventStreamCallback =
	{ _, info, eventCount, eventPaths, eventFlags, eventIdentifiers in
		guard let info else { return }
		let session = Unmanaged<FileSystemEventSession>.fromOpaque(info).takeUnretainedValue()
		/* eventPaths is a borrowed CFArray; bit-casting it would hand ARC an
		 unbalanced release at the end of scope. */
		let paths = Unmanaged<NSArray>.fromOpaque(eventPaths).takeUnretainedValue()
		session.receive(paths: paths, flags: eventFlags, identifiers: eventIdentifiers, count: eventCount)
	}
