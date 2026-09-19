// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The `os.Logger` subsystem every logger in the application and in the
/// connection host names.
///
/// One declaration rather than a literal per logger: `scripts/smoke.sh` gates a
/// run on `subsystem BEGINSWITH "com.vakesz"`, and a fallback spelled anything
/// else would hide an error or fault from it. The bundle identifier is the
/// running product's own, so the app and the host stay apart in the log; the
/// fallback is only reached by a process with no `Info.plist`.
nonisolated enum LogSubsystem {
	/// The running product's own subsystem: the application in the application,
	/// the connection host in the host.
	static let current = Bundle.main.bundleIdentifier ?? application

	/// The application's subsystem, named rather than read from the running
	/// bundle. A trace both processes write into is one sequence of milestones in
	/// one log stream whichever side emitted them.
	static let application = "com.vakesz.glasstual"
}
