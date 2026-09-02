/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@Suite("Transcript logger idle sweep")
struct FileLoggerIdleSweepTests {
	@Test("A handle that was never written to is never swept")
	func unwrittenHandleIsNotIdle() {
		#expect(FileLogger.fileHandleIsIdle(lastWriteTime: 0, at: 100_000) == false)
	}

	@Test(
		"A handle is swept only once nothing has been written for the idle limit",
		arguments: [
			(secondsSinceWrite: 0.0, idle: false),
			(secondsSinceWrite: 1199.0, idle: false),
			(secondsSinceWrite: 1200.0, idle: false),
			(secondsSinceWrite: 1201.0, idle: true),
			(secondsSinceWrite: 10000.0, idle: true),
		]
	)
	func idleLimitBoundary(secondsSinceWrite: Double, idle: Bool) {
		let lastWriteTime = 1_000_000.0

		#expect(
			FileLogger.fileHandleIsIdle(
				lastWriteTime: lastWriteTime,
				at: lastWriteTime + secondsSinceWrite
			) == idle
		)
	}
}
