// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Where this Mac keeps its configuration backups. Launch repair and the
/// settings transfer feature both read it from here.
enum SettingsRecoveryDirectory {
	static var url: URL {
		(ApplicationPaths.applicationSupportURL ?? URL.applicationSupportDirectory)
			.appendingPathComponent("Configuration Backups", isDirectory: true)
	}
}
