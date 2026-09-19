// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Where a watched person stands, as the last WATCH, MONITOR or ISON answer
 left them.

 The raw values travel in the `addressBookTrackingStatusKey` notification
 payload, so they are a wire vocabulary and not just an ordering. */
enum AddressBookUserTrackingStatus: UInt, Sendable {
	case unknown = 0
	case signedOff = 1
	case signedOn = 2
	case available = 3
	case notAvailable = 4
	case away = 5
	case notAway = 6
}
