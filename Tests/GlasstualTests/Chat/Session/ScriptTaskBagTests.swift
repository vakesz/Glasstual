// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Script task bag", .timeLimit(.minutes(1)))
struct ScriptTaskBagTests {
	@Test("Cancelling the bag cancels the scripts still running")
	func cancelAllCancelsRunningScripts() async {
		let bag = ScriptTaskBag()
		let (started, startedContinuation) = AsyncStream<Void>.makeStream()
		let (finished, finishedContinuation) = AsyncStream<Bool>.makeStream()

		bag.run {
			startedContinuation.yield()
			while Task.isCancelled == false {
				await Task.yield()
			}
			finishedContinuation.yield(true)
		}

		var startedIterator = started.makeAsyncIterator()
		await startedIterator.next()
		bag.cancelAll()

		var finishedIterator = finished.makeAsyncIterator()
		#expect(await finishedIterator.next() == true)
	}
}
