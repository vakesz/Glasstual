// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension BouncerNetworkStatus {
	/// The line under a network's name, also read out by VoiceOver.
	var text: String {
		switch self {
		case .connecting: String(localized: .Sidebar.bouncerStatusConnecting)
		case .disconnected: String(localized: .Sidebar.bouncerStatusDisconnected)
		case let .failed(reason): String(localized: .Sidebar.bouncerStatusFailed(reason))
		case .removed: String(localized: .Sidebar.bouncerStatusRemoved)
		}
	}
}
