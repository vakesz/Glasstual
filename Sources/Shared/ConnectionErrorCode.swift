// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated let connectionErrorDomain = "Glasstual.ConnectionError"

/// Error codes exchanged across the remote-connection XPC boundary.
///
/// These values are part of the service wire contract and must not change.
enum ConnectionErrorCode: UInt, Sendable {
	case socket = 999
	case other = 1000
	case badCertificate = 1001
	case unableToSecure = 1002
}
