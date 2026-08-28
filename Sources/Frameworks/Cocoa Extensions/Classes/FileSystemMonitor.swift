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

public typealias FileSystemMonitorCallback = ([XRFileSystemEvent]) -> Void

@objc(XRFileSystemEvent)
@objcMembers
public final class XRFileSystemEvent: NSObject, @unchecked Sendable {
	public let url: URL
	public let flags: FSEventStreamEventFlags
	public let identifier: FSEventStreamEventId
	public let context: Any?

	init(url: URL, flags: FSEventStreamEventFlags, identifier: FSEventStreamEventId, context: Any?) {
		self.url = url
		self.flags = flags
		self.identifier = identifier
		self.context = context
		super.init()
	}
}

@objc(XRFileSystemMonitor)
@objcMembers
public final class XRFileSystemMonitor: NSObject, @unchecked Sendable {
	private let urls: [URL]
	private let callback: FileSystemMonitorCallback
	private let contexts: [String: Any]
	private let lock = NSLock()
	private var eventStream: FSEventStreamRef?

	@objc(initWithFileURL:callbackBlock:)
	public convenience init(fileURL: URL, callback: @escaping FileSystemMonitorCallback) {
		self.init(fileURLs: [fileURL], contexts: nil, callback: callback)
	}

	@objc(initWithFileURL:context:callbackBlock:)
	public convenience init(fileURL: URL, context: Any?, callback: @escaping FileSystemMonitorCallback) {
		self.init(fileURLs: [fileURL], contexts: context.map { [fileURL: $0] }, callback: callback)
	}

	@objc(initWithFileURLs:callbackBlock:)
	public convenience init(fileURLs: [URL], callback: @escaping FileSystemMonitorCallback) {
		self.init(fileURLs: fileURLs, contexts: nil, callback: callback)
	}

	@objc(initWithFileURLs:context:callbackBlock:)
	public init(fileURLs: [URL], contexts: [URL: Any]?, callback: @escaping FileSystemMonitorCallback) {
		precondition(fileURLs.isEmpty == false)
		urls = fileURLs.map(\.standardizedFileURL)
		self.callback = callback
		self.contexts = Dictionary(uniqueKeysWithValues: (contexts ?? [:]).map {
			($0.key.standardizedFileURL.path, $0.value)
		})
		super.init()
	}

	deinit {
		stopMonitoring()
	}

	public var isMonitoring: Bool {
		lock.withLock { eventStream != nil }
	}

	public func startMonitoring() {
		startMonitoring(withLatency: 0)
	}

	@objc(startMonitoringWithLatency:)
	public func startMonitoring(withLatency latency: TimeInterval) {
		precondition(latency >= 0)
		let paths = urls.map(\.path) as CFArray
		var context = FSEventStreamContext(
			version: 0,
			info: Unmanaged.passUnretained(self).toOpaque(),
			retain: nil,
			release: nil,
			copyDescription: nil
		)
		let flags = FSEventStreamCreateFlags(
			kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
		)

		/* Create-through-assign has to be atomic: two concurrent starts would otherwise
		 both create and start a stream, and the loser would never be stored or stopped
		 while still delivering callbacks through an unretained pointer to self. */
		lock.lock()
		defer { lock.unlock() }

		tearDownStreamLocked()

		guard let stream = FSEventStreamCreate(
			nil,
			fileSystemMonitorCallback,
			&context,
			paths,
			FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
			latency,
			flags
		) else { return }
		FSEventStreamSetDispatchQueue(stream, .main)
		guard FSEventStreamStart(stream) else {
			FSEventStreamInvalidate(stream)
			FSEventStreamRelease(stream)
			return
		}
		eventStream = stream
	}

	public func stopMonitoring() {
		lock.lock()
		defer { lock.unlock() }
		tearDownStreamLocked()
	}

	private func tearDownStreamLocked() {
		guard let stream = eventStream else { return }
		eventStream = nil
		FSEventStreamStop(stream)
		FSEventStreamInvalidate(stream)
		FSEventStreamRelease(stream)
	}

	@objc(contextObjectForURL:)
	public func contextObject(for url: URL) -> Any? {
		contexts[url.standardizedFileURL.path]
	}

	fileprivate func receive(
		paths: NSArray,
		flags: UnsafePointer<FSEventStreamEventFlags>,
		identifiers: UnsafePointer<FSEventStreamEventId>,
		count: Int
	) {
		var events: [XRFileSystemEvent] = []
		events.reserveCapacity(count)
		for index in 0 ..< count {
			guard let path = paths[index] as? String else { continue }
			let url = URL(fileURLWithPath: path)
			events.append(XRFileSystemEvent(
				url: url,
				flags: flags[index],
				identifier: identifiers[index],
				context: contextObject(for: url)
			))
		}
		callback(events)
	}
}

private let fileSystemMonitorCallback: FSEventStreamCallback =
	{ _, info, eventCount, eventPaths, eventFlags, eventIdentifiers in
		guard let info else { return }
		let monitor = Unmanaged<XRFileSystemMonitor>.fromOpaque(info).takeUnretainedValue()
		/* eventPaths is a borrowed CFArray; bit-casting it would hand ARC an
		 unbalanced release at the end of scope. */
		let paths = Unmanaged<NSArray>.fromOpaque(eventPaths).takeUnretainedValue()
		monitor.receive(paths: paths, flags: eventFlags, identifiers: eventIdentifiers, count: eventCount)
	}
