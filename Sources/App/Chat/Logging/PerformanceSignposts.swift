// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import os

/** Signpost intervals around the hot path from socket to screen.

 Intervals cost almost nothing while no tool is recording. To profile, record
 with Instruments using the "os_signpost" instrument (or the Logging template)
 and filter on subsystem `com.vakesz.glasstual`, category `Performance`:

 - `InboundLine`: one received line, parsed and handled by its session.
 - `ApplyPrintedLine`: a rendered line applied to the transcript, the
   projection and the scrollback store.
 - `TranscriptInsert`: rows rendered and spliced into the text storage.

 A run of long `InboundLine` intervals names a handler; `ApplyPrintedLine`
 that mostly contains `TranscriptInsert` points at TextKit. Run from Xcode
 with Product > Profile, or attach to a running build. */
nonisolated enum PerformanceSignposts {
	static let signposter = OSSignposter(subsystem: LogSubsystem.current, category: "Performance")
}
