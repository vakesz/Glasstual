// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Synchronization
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct FileTransferWorkspaceTests {
	private let file = FileTransferLocalFile(url: URL(filePath: "/download.txt"), accessURL: URL(filePath: "/downloads"))

	@Test("Cancellation before an open starts never reaches LaunchServices")
	func cancelledBeforeStarting() async {
		var opens = 0
		let workspace = FileTransferWorkspace(openFile: { _ in opens += 1 })
		workspace.open([file])
		let tasks = Array(workspace.openTasks.values)
		workspace.cancelPendingWork()
		for task in tasks {
			await task.value
		}
		#expect(opens == 0)
		#expect(workspace.openTasks.isEmpty)
	}

	@Test("In-flight opens keep their access until LaunchServices returns", arguments: [false, true])
	func accessSurvivesCancellation(fails: Bool) async {
		let stopped = Mutex(0)
		let (started, signal) = AsyncStream<Void>.makeStream()
		var completion: CheckedContinuation<Void, any Error>?
		let workspace = FileTransferWorkspace(openFile: { _ in
			try await withCheckedThrowingContinuation {
				completion = $0
				signal.yield()
			}
		}, acquireAccess: { url in
			FileTransferAccessLease(url: url, startAccess: { _ in true }, stopAccess: { _ in stopped.withLock { $0 += 1 } })
		})
		workspace.open([file])
		let tasks = Array(workspace.openTasks.values)
		var events = started.makeAsyncIterator()
		_ = await events.next()
		workspace.cancelPendingWork()
		#expect(stopped.withLock { $0 } == 0)
		if fails {
			completion?.resume(throwing: CocoaError(.fileReadUnknown))
		} else {
			completion?.resume()
		}
		completion = nil
		for task in tasks {
			await task.value
		}
		#expect(stopped.withLock { $0 } == 1)
		#expect(workspace.openTasks.isEmpty)
		signal.finish()
	}
}
