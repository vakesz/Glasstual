/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions

/** Where each window's saved frame lives.

 These strings are on disk in every existing installation, under the
 `NSWindow Frame -> Internal (v3) -> ` prefix, so they are the Objective-C class
 names the port inherited and must stay spelled that way. They used to be
 produced by `NSStringFromClass`, which tied a user's window position to an
 `` name that had no other reason to exist. */
public extension WindowStateKey {
	static let preferences = Self(rawValue: "TDCPreferencesController")
	static let serverChannelList = Self(rawValue: "TDCServerChannelListDialog")
	static let about = Self(rawValue: "TDCAboutDialog")
	static let channelSpotlight = Self(rawValue: "TDCChannelSpotlightController")
	static let fileTransfers = Self(rawValue: "TDCFileTransferDialog")
}
