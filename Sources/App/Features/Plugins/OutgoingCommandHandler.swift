/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

/** What an add-on command typed into the input field is dispatched to.

 The client asks this before falling back to sending the command to the server
 as a raw line. Both an AppleScript and a loaded plugin can declare the same
 name, which is nothing the client can choose between, so that is a case of its
 own rather than a silent preference for one of them. */
public nonisolated enum OutgoingCommandHandler: Equatable, Sendable { // nonisolated: value
	/// Nothing claims the command.
	case none
	/// A script at this path. Kept as a path for existing command consumers.
	case script(path: String)
	/// A loaded plugin that declares the command.
	case pluginExtension
	/// Both a script and a plugin claim it.
	case ambiguous
}
