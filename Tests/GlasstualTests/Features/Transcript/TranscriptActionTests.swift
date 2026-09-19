// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript click targets")
struct TranscriptActionTests {
	/** Both values are boxed into attributes, so the text storage compares and
	 coalesces runs by calling `-isEqual:` and `-hash` on the box. A value that
	 is only `Equatable` is hashed by the runtime's fallback, which logs "Obj-C
	 `-hash` invoked on a Swift value ... that is Equatable but not Hashable" on
	 every transcript render and gives every value of the type the same hash.
	 Asking the bridged box for its hash is what pins the conformance: it is the
	 call the storage makes, and only a `Hashable` value answers it with its
	 own. */
	@Test("The boxed attribute values hash as themselves")
	func attributeValuesAreHashable() {
		let nickname = TranscriptAction.nickname("alice")
		let channel = TranscriptAction.channel("#glasstual")
		#expect((nickname as AnyObject).hash != (channel as AnyObject).hash)
		#expect((nickname as AnyObject).hash == (TranscriptAction.nickname("alice") as AnyObject).hash)

		let target = TranscriptReactionTarget(messageIdentifier: "msg-1", emoji: "\u{1F44D}")
		let other = TranscriptReactionTarget(messageIdentifier: "msg-2", emoji: "\u{1F44D}")
		#expect((target as AnyObject).hash != (other as AnyObject).hash)
		#expect(
			(target as AnyObject).hash
				== (TranscriptReactionTarget(messageIdentifier: "msg-1", emoji: "\u{1F44D}") as AnyObject).hash
		)
	}
}
