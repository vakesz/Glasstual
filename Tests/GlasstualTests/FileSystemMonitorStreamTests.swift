/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Testing

/// Nonisolated: `XRFileSystemMonitor` is, and both tests need the writer and
/// the consumer to run at the same time. On the main actor they would take
/// turns, which is not the shape FSEvents is being asked about.
@Suite("File-system monitor stream")
nonisolated struct FileSystemMonitorStreamTests {
	@Test("The stream reports a file written into a watched folder")
	func reportsAWrite() async throws {
		let folder = try makeTemporaryFolder()
		defer { try? FileManager.default.removeItem(at: folder) }

		var iterator = XRFileSystemMonitor.events(for: folder).makeAsyncIterator()

		let file = folder.appendingPathComponent("written.txt", isDirectory: false)
		let writer = Task {
			/* FSEvents needs the stream running before the change happens, and
			 there is no callback that says "started"; poll instead of guessing
			 a single sleep length. */
			for _ in 0 ..< 50 {
				try? Data("hello".utf8).write(to: file)
				try? await Task.sleep(for: .milliseconds(100))
			}
		}
		defer { writer.cancel() }

		let events = await iterator.next()
		let reported = try #require(events)

		#expect(reported.isEmpty == false)
		#expect(reported.contains { $0.url.lastPathComponent == "written.txt" })
	}

	@Test("Cancelling the consuming task terminates the stream")
	func cancellationTerminatesTheStream() async throws {
		let folder = try makeTemporaryFolder()
		defer { try? FileManager.default.removeItem(at: folder) }

		let started = AsyncStream<Void>.makeStream()

		let consumer = Task {
			started.continuation.yield()
			started.continuation.finish()

			for await _ in XRFileSystemMonitor.events(for: folder) {
				/* Drain until cancelled. */
			}

			return true
		}

		for await _ in started.stream {
			break
		}

		consumer.cancel()

		/* The loop only returns once the stream has terminated, which is what
		 tears the FSEvents stream down. A hung teardown would hang here. */
		#expect(await consumer.value)
	}

	private func makeTemporaryFolder() throws -> URL {
		let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent("FileSystemMonitorStreamTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		/* FSEvents reports the resolved path, and the temporary directory is a
		 symlink on macOS. */
		return folder.resolvingSymlinksInPath()
	}
}
