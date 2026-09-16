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

/** What a command typed into the input field is dispatched to when the client
 has no built-in handler for it.

 The client asks this before falling back to sending the command to the server
 as a raw line. */
nonisolated enum OutgoingCommandOwner: Equatable, Sendable { // nonisolated: value
	/// Nothing claims the command, so it goes to the server as written.
	case none
	/// A user script at this path. Kept as a path for existing command consumers.
	case script(path: String)
}
