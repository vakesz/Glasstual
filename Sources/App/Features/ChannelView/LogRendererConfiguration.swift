/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

/// Editor presentation stays on the main actor and never enters a render job.
struct LogRendererConfiguration {
	var preferredFont: NSFont?
	var preferredFontColor: NSColor?
}

nonisolated struct TranscriptRenderOptions: Sendable { // nonisolated: value
	var renderLinks = false
	var lineType = LogLineType.undefined
	var memberType = LogLineMemberType.normal
	var highlightKeywords: [String] = []
	var excludedKeywords: [String] = []
}
