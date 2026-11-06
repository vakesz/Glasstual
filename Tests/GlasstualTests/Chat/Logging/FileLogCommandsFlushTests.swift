// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("File log flush", .timeLimit(.minutes(1)))
struct FileLogCommandsFlushTests {
	@Test("A flush on an idle stream reports success")
	func flushReportsSuccess() async {
		let sink = RecordingFileLogSink()
		let commands = FileLogCommands(sink: FileLogSinkPort { await sink.process($0) })

		#expect(await commands.flush())
	}

	@Test("A cancelled caller is released without waiting for the stream")
	func cancelledFlushReturnsFalse() async {
		let sink = RecordingFileLogSink()
		let commands = FileLogCommands(sink: FileLogSinkPort { await sink.process($0) })
		let flush = Task { await commands.flush() }
		flush.cancel()

		#expect(await flush.value == false)
	}

	@Test("A flush after the stream finished reports failure")
	func flushAfterFinishReturnsFalse() async {
		let sink = RecordingFileLogSink()
		let commands = FileLogCommands(sink: FileLogSinkPort { await sink.process($0) })
		commands.finish { _ in }

		#expect(await commands.flush() == false)
	}
}
