// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

/// What the connection configuration records when it cannot be taken at face
/// value. The configuration is compiled into the app and the connection host,
/// and each logs under its own subsystem.
public nonisolated enum ConnectionConfigurationLog {
	private static let logger = Logger(subsystem: LogSubsystem.current, category: "ConnectionConfig")

	public static func unsupportedProxyType(_ rawValue: UInt) {
		logger.error(
			"Unsupported proxy type \(rawValue, privacy: .public) in stored configuration; using no proxy"
		)
	}

	public static func unreadableConfiguration() {
		logger.error("Received a connection configuration that could not be read")
	}

	public static func unwritableConfiguration() {
		logger.error("Could not write a connection configuration for the connection host")
	}
}
