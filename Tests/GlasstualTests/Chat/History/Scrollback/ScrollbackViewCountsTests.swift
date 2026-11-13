// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Scrollback view counts")
struct ScrollbackViewCountsTests {
	private func pass() -> ScrollbackViewCounts.ScheduledResize {
		ScrollbackViewCounts.ScheduledResize(
			identifier: UUID(),
			task: Task { try? await Task.sleep(for: .seconds(3600)) }
		)
	}

	@Test("A lowered limit retires armed passes and offers every view for a new one")
	func loweredLimitRetiresArmedPasses() {
		var counts = ScrollbackViewCounts()
		counts.insert("long", lineCount: 150, maximumIdentifier: 150)
		counts.insert("short", lineCount: 10, maximumIdentifier: 10)
		let armed = pass()
		counts.armResize("long", armed)
		#expect(counts.needsResize("long") == false)

		let views = counts.setMaximumLineCount(50)

		#expect(Set(views) == ["long", "short"])
		#expect(armed.task.isCancelled)
		#expect(counts.needsResize("long"))
		#expect(counts.needsResize("short") == false)
	}

	@Test("A raised limit keeps the armed pass, and a zero limit is ignored")
	func raisedLimitKeepsArmedPass() {
		var counts = ScrollbackViewCounts()
		counts.insert("long", lineCount: 150, maximumIdentifier: 150)
		let armed = pass()
		counts.armResize("long", armed)

		let ignored = counts.setMaximumLineCount(0)
		#expect(ignored.isEmpty)
		#expect(counts.maximumLineCount == 100)
		let raised = counts.setMaximumLineCount(200)
		#expect(raised == ["long"])
		#expect(armed.task.isCancelled == false)
		#expect(counts.isCurrent(armed.identifier, for: "long"))
		armed.task.cancel()
	}

	@Test("A stale pass does not release a newer one")
	func stalePassKeepsNewerSlot() {
		var counts = ScrollbackViewCounts()
		counts.insert("view", lineCount: 150, maximumIdentifier: 150)
		let armed = pass()
		counts.armResize("view", armed)

		counts.releaseResizeSlot("view", requestIdentifier: UUID())
		#expect(counts.isCurrent(armed.identifier, for: "view"))

		counts.releaseResizeSlot("view", requestIdentifier: armed.identifier)
		#expect(counts.isCurrent(armed.identifier, for: "view") == false)
		#expect(counts.needsResize("view"))
		armed.task.cancel()
	}

	@Test("Counts saturate instead of wrapping")
	func countsSaturate() {
		var counts = ScrollbackViewCounts()
		counts.insert("full", lineCount: .max, maximumIdentifier: 1)
		counts.insert("small", lineCount: 3, maximumIdentifier: 3)

		counts.noteInserted("full", entryIdentifier: 2)
		counts.subtract(5, from: "small")

		#expect(counts.maximumIdentifier(of: "full") == 2)
		#expect(counts.needsResize("full"))
		let views = counts.setMaximumLineCount(1)
		#expect(views.count == 2)
		#expect(counts.needsResize("small") == false)
		#expect(saturatedAdd(.max, 1) == .max)
		#expect(saturatedAdd(2, 3) == 5)
	}
}
