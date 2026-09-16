/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// What the negotiated session lets the client do, read by everything past
/// registration. The negotiation that produces these answers lives in
/// `ClientNegotiation`.
extension Client {
	func isCapabilityEnabled(_ capability: CapabilitySet) -> Bool {
		capabilities.contains(capability)
	}

	func isCapabilitySupported(_ capability: String) -> Bool {
		CapabilityRegistry.defaultRegistry.isCapabilitySupported(capability, preferences: environment.preferences)
	}

	var enabledCapabilitiesStringValue: String {
		capabilityNegotiation.enabledCapabilitiesStringValue
	}

	/// Whether the server tracks presence for the client, through `MONITOR`
	/// or `WATCH`.
	var supportsAdvancedTracking: Bool {
		isCapabilityEnabled(.monitorCommand) || isCapabilityEnabled(.watchCommand)
	}

	/// Whether member away state is kept current, by `away-notify` or by the
	/// user's own polling preference.
	var monitorAwayStatus: Bool {
		isCapabilityEnabled(.awayNotify) || environment.preferences.trackUserAwayStatusMaximumChannelSize > 0
	}
}
