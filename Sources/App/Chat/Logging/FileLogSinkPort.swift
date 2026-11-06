// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Where a file-log operation is carried out.

 A value holding one closure rather than a protocol: the only thing that varies
 is which actor is behind it, and the one production actor is
 ``FileLogSink``. */
nonisolated struct FileLogSinkPort: Sendable {
	let process: @Sendable (FileLogOperation) async -> FileLogResult

	/// The real transcript files on disk.
	static func fileSystem() -> Self {
		let sink = FileLogSink()

		return Self { await sink.process($0) }
	}
}
