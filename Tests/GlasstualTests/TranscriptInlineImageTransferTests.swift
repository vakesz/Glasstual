/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// Cancelling a download tears the session down. If that lands before the
/// continuation is installed, nothing is left to resume it and the task hangs
/// for good, which is what this covers.
@Suite("Transcript inline image transfer")
struct TranscriptInlineImageTransferTests {
	@Test("A cancelled download finishes rather than waiting on a session that is gone", .timeLimit(.minutes(1)))
	func aCancelledDownloadFinishes() async throws {
		let url = try #require(URL(string: "https://example.invalid/never-answers.png"))
		let task = Task.detached {
			try await NativeInlineImageTransfer.download(
				url,
				limits: NativeInlineImageLimits(),
				protocolClasses: []
			)
		}
		task.cancel()
		await #expect(throws: (any Error).self) {
			try await task.value
		}
	}
}
