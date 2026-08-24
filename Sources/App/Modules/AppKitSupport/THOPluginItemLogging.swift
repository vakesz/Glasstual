/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2024 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
import os

private nonisolated(unsafe) let pluginLoggingSubsystems = NSCache<NSString, OSLog>()

@_cdecl("_THOPluginLoggingSubsystemForBundle")
public func _THOPluginLoggingSubsystemForBundle(_ bundle: Bundle) -> OSLog {
	objc_sync_enter(pluginLoggingSubsystems)
	defer { objc_sync_exit(pluginLoggingSubsystems) }

	let identifier = (bundle.bundleIdentifier ?? "") as NSString

	if let subsystem = pluginLoggingSubsystems.object(forKey: identifier) {
		return subsystem
	}

	let category = "Extension['\(bundle.displayName ?? "")']"
	let subsystem = OSLog(
		subsystem: Bundle.main.bundleIdentifier ?? TXBundleBuildProductIdentifier,
		category: category
	)

	pluginLoggingSubsystems.setObject(subsystem, forKey: identifier)

	return subsystem
}
