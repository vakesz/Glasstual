/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
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
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
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

import Foundation
@testable import Glasstual
import Synchronization
import Testing

/// Records the KVO transitions an operation publishes, in order.
private func transitions(
	of operation: LogControllerPrintingOperation,
	while body: () -> Void
) -> [String] {
	let recorded = Mutex<[String]>([])
	let observations = [
		operation.observe(\.isExecuting, options: .new) { _, change in
			recorded.withLock { $0.append("executing=\(change.newValue == true)") }
		},
		operation.observe(\.isFinished, options: .new) { _, change in
			recorded.withLock { $0.append("finished=\(change.newValue == true)") }
		},
	]
	body()
	for observation in observations {
		observation.invalidate()
	}
	return recorded.withLock { $0 }
}

private func makeOperation(explicitFinish: Bool, standalone: Bool = true) -> LogControllerPrintingOperation {
	let operation = LogControllerPrintingOperation()
	operation.requiresExplicitFinish = explicitFinish
	operation.standalone = standalone
	operation.pendingOperationsKey = "view"
	return operation
}

@Suite("Log controller printing operation")
struct LogControllerPrintingOperationTests {
	@Test("A fresh operation is pending and neither executing nor finished")
	func freshOperationIsPending() {
		let operation = makeOperation(explicitFinish: true)

		#expect(operation.isPending)
		#expect(operation.isExecuting == false)
		#expect(operation.isFinished == false)
	}

	@Test("An asynchronous operation reports executing before it reports finished")
	func asynchronousOperationTransitionsInOrder() {
		let operation = makeOperation(explicitFinish: true)

		/* With no view controller attached, `start()` runs the block (which does
		 nothing) and then finishes the operation itself, so a single call walks
		 the whole state machine. */
		let recorded = transitions(of: operation) { operation.start() }

		#expect(recorded == ["executing=true", "finished=true", "executing=false"])
		#expect(operation.isExecuting == false)
		#expect(operation.isFinished)
		#expect(operation.isPending == false)
	}

	@Test("Finishing an operation more than once transitions it once")
	func finishingTwiceTransitionsOnce() {
		let operation = makeOperation(explicitFinish: true)
		operation.start()

		let recorded = transitions(of: operation) {
			operation.finish()
			operation.finish()
		}

		#expect(recorded.isEmpty)
		#expect(operation.isFinished)
	}

	@Test("Cancelling an operation before it starts finishes it")
	func cancellingBeforeStartFinishes() {
		let operation = makeOperation(explicitFinish: true)

		let recorded = transitions(of: operation) { operation.cancel() }

		#expect(recorded == ["finished=true", "executing=false"])
		#expect(operation.isCancelled)
		#expect(operation.isFinished)
		#expect(operation.isExecuting == false)
	}

	@Test("Starting a cancelled operation does not re-enter the state machine")
	func startingAfterCancellationIsInert() {
		let operation = makeOperation(explicitFinish: true)
		operation.cancel()

		let recorded = transitions(of: operation) { operation.start() }

		#expect(recorded.isEmpty)
		#expect(operation.isFinished)
	}

	@Test("A synchronous operation finishes without an explicit call")
	func synchronousOperationFinishesOnItsOwn() {
		let operation = makeOperation(explicitFinish: false)

		#expect(operation.isAsynchronous == false)
		operation.start()

		#expect(operation.isFinished)
		#expect(operation.isExecuting == false)
	}

	@Test("Finishing a synchronous operation is ignored")
	func finishingSynchronousOperationIsIgnored() {
		let operation = makeOperation(explicitFinish: false)

		operation.finish()

		#expect(operation.isFinished == false)
	}

	@Test("The cached view load state survives a round trip")
	func viewLoadStateRoundTrips() {
		let operation = makeOperation(explicitFinish: true)

		#expect(operation.viewIsLoaded == false)
		operation.viewIsLoaded = true
		#expect(operation.viewIsLoaded)
	}

	@Test(
		"An operation that heads its own chain waits for the view it prints into",
		arguments: [
			// dependenciesAreReady, hasDependencies, standalone, hasViewController, viewIsLoaded, expected
			(true, false, false, true, false, false),
			(true, false, false, true, true, true),
			(true, false, false, false, false, true),
			(false, false, false, true, true, false),
			(true, true, false, true, false, true),
			(false, true, false, true, true, false),
			(true, true, true, true, false, false),
		]
	)
	func readinessRule(
		dependenciesAreReady: Bool,
		hasDependencies: Bool,
		standalone: Bool,
		hasViewController: Bool,
		viewIsLoaded: Bool,
		expected: Bool
	) {
		let isReady = LogControllerPrintingOperation.isReady(
			dependenciesAreReady: dependenciesAreReady,
			hasDependencies: hasDependencies,
			standalone: standalone,
			hasViewController: hasViewController,
			viewIsLoaded: viewIsLoaded
		)

		#expect(isReady == expected)
	}
}
