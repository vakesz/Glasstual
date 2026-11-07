// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

// Prints the CGWindowID of an on-screen window for scripts/website-screenshots.sh.
//   website-window-id <pid> [title-prefix]
// Prints the identifier of the largest matching normal-layer window, or exits 1
// when none is on screen. Window titles need the Screen Recording grant; a
// title-prefix filter finds nothing without it, which the script reports.
// "website-window-id --capture-allowed" exits 0 when Screen Recording is granted.

import CoreGraphics
import Foundation

let arguments = CommandLine.arguments

if arguments.count == 2, arguments[1] == "--capture-allowed" {
	exit(CGPreflightScreenCaptureAccess() ? 0 : 1)
}

guard arguments.count >= 2, let pid = Int32(arguments[1]) else {
	FileHandle.standardError.write(Data("usage: website-window-id <pid> [title-prefix]\n".utf8))
	exit(2)
}
let prefix = arguments.count > 2 ? arguments[2] : nil

let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
var best: (identifier: Int, area: Double)?
for window in windows {
	guard let owner = window[kCGWindowOwnerPID as String] as? Int32, owner == pid,
	      let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
	      let identifier = window[kCGWindowNumber as String] as? Int,
	      let bounds = window[kCGWindowBounds as String] as? [String: Double],
	      let width = bounds["Width"], let height = bounds["Height"], width > 100, height > 100
	else { continue }
	if let prefix {
		let title = window[kCGWindowName as String] as? String ?? ""
		guard title.hasPrefix(prefix) else { continue }
	}
	if best == nil || width * height > best!.area {
		best = (identifier, width * height)
	}
}
guard let best else { exit(1) }
print(best.identifier)
