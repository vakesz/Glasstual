/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

/// Typed host boundary used by plugins that present the native server and
/// channel selection view supplied by Glasstual.
@MainActor
public protocol PluginChannelSelection: AnyObject {
	var selectedClientIds: [String] { get set }
	var selectedChannelIds: [String] { get set }

	func attach(to view: NSView)
}
