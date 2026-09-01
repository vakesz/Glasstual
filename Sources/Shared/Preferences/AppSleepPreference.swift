/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// AppKit reads this process-local key directly to decide whether App Nap is
/// disabled. Both the app and the connection host own a value in their own
/// defaults domain, so the spelling is a shared process-boundary contract.
public nonisolated enum AppSleepPreference { // nonisolated: value
	public static let name = "NSAppSleepDisabled"
}
