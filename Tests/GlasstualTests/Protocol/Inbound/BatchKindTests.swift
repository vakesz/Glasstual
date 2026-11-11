// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

struct BatchKindTests {
	@Test(
		"Each spelling of a known batch type reads as its kind",
		arguments: [
			("chathistory", BatchKind.chatHistory), ("draft/chathistory", .chatHistory),
			("draft/multiline", .multiline), ("multiline", .multiline),
			("soju.im/bouncer-networks", .bouncerNetworks),
			("netsplit", .netsplit), ("netjoin", .netjoin),
			("playback", .playback), ("znc.in/playback", .zncPlayback), ("znc.in/tlsinfo", .zncTLSInfo),
			("draft/isupport", .isupport), ("isupport", .isupport),
		]
	)
	func knownSpellingsAreRecognised(_ testCase: (type: String, kind: BatchKind)) {
		#expect(BatchKind(wireType: testCase.type) == testCase.kind)
	}

	@Test("A type this client does not know keeps its text")
	func unknownTypesRoundTrip() {
		for type in ["x-foo/bar", "NETSPLIT", "draft/netsplit", ""] {
			let kind = BatchKind(wireType: type)
			#expect(kind == .other(type))
			#expect(kind.wireType == type)
		}
	}

	@Test("Netsplit and netjoin stay apart, as do bare and ZNC playback")
	func similarKindsAreDistinct() {
		#expect(BatchKind.netsplit != .netjoin)
		#expect(BatchKind.playback != .zncPlayback)
	}

	@Test("Only chat history and playback batches replay earlier lines")
	func replayKinds() {
		#expect(BatchKind.chatHistory.isReplay)
		#expect(BatchKind.playback.isReplay)
		#expect(BatchKind.zncPlayback.isReplay)
		#expect(BatchKind.zncTLSInfo.isReplay == false)
		#expect(BatchKind.netsplit.isReplay == false)
		#expect(BatchKind.other("x").isReplay == false)
	}

	@Test("The wire spelling on a batch is left as the server wrote it")
	func batchTypeIsNotRewritten() {
		let batch = MessageBatch()
		batch.batchType = "draft/chathistory"
		#expect(batch.kind == .chatHistory)
		#expect(batch.batchType == "draft/chathistory")
	}
}
