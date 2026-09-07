/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/** What a caller's completion block is told about the line it printed.

 A value, and only ever read: the client and the channel are weak because the
 completion may run after either has been torn down, and everything else is the
 rendered outcome the caller asked to hear about. */
public struct LogControllerPrintOperationContext {
	public private(set) weak var client: IRCClient?
	public private(set) weak var channel: IRCChannel?
	public let isHighlight: Bool
	public let logLine: LogLine
	public let lineNumber: String

	init(client: IRCClient, channel: IRCChannel?, highlight: Bool, logLine: LogLine, lineNumber: String) {
		self.client = client
		self.channel = channel
		isHighlight = highlight
		self.logLine = logLine
		self.lineNumber = lineNumber
	}
}
