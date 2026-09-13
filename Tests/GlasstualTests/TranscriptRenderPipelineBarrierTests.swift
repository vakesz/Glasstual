/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

/// A barrier stores its continuation on the actor and its cancellation handler
/// hops back to the same actor to resume it. Either can land first, and the one
/// that arrives last has to be the one that resumes.
@Suite("Transcript render pipeline barriers")
struct TranscriptRenderPipelineBarrierTests {
	@Test("Cancelling a barrier ends it instead of leaving it waiting", .timeLimit(.minutes(1)))
	func aCancelledBarrierEnds() async {
		let pipeline = LogRenderPipeline()
		let task = Task { await pipeline.barrier() }
		task.cancel()
		await task.value
		await pipeline.stop()
	}
}
