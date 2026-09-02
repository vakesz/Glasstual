/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

/** The raw values are persisted — they are written into the renderer
 attribute dictionary and archived with every log line — so a number may never
 be reused and a new case may only ever be appended. `offTheRecordEncryptionStatus`
 stays at 15 for the sake of already-archived lines even though OTR is gone. */
public enum LogLineType: UInt, Codable, Sendable {
	case undefined = 0
	case action = 1
	case actionNoHighlight = 2
	case ctcp = 3
	case ctcpQuery = 4
	case ctcpReply = 5
	case dccFileTransfer = 6
	case debug = 7
	case invite = 8
	case join = 9
	case kick = 10
	case kill = 11
	case mode = 12
	case nick = 13
	case notice = 14
	case offTheRecordEncryptionStatus = 15
	case part = 16
	case privateMessage = 17
	case privateMessageNoHighlight = 18
	case quit = 19
	case topic = 20
	case website = 21

	/// Something a person said, as opposed to an event the client narrates —
	/// a join, a mode, a topic. The unread marker is placed before the first
	/// of these, not before the first line of any kind.
	public nonisolated var isConversation: Bool { // nonisolated: value
		switch self {
		case .action, .actionNoHighlight, .notice, .privateMessage, .privateMessageNoHighlight:
			true
		default:
			false
		}
	}
}

/** Persisted alongside the log line; see `LogLineType`. */
public enum LogLineMemberType: UInt, Codable, Sendable {
	case normal = 0
	case localUser = 1
}

/** Persisted alongside the log line; see `LogLineType`. */
public enum LogLineDeliveryState: UInt, Codable, Sendable {
	case none = 0
	case pending = 1
	case delivered = 2
	case failed = 3
}
