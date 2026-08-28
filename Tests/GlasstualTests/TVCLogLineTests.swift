/*  *********************************************************************
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
@testable import Glasstual
import Testing

@MainActor
@Suite("Log line")
struct TVCLogLineTests {
	@Test("The message identifier survives a copy and a secure-coding round trip")
	func messageIdentifierSurvivesArchivingAndCopying() throws {
		let line = LogLine()
		line.command = "privmsg"
		line.lineType = .privateMessage
		line.nickname = "alice"
		line.messageBody = "hello"
		line.messageIdentifier = "63E1033A0"

		let copy = line.duplicate()
		#expect(copy.messageIdentifier == "63E1033A0")

		let data = try NSKeyedArchiver.archivedData(withRootObject: copy, requiringSecureCoding: true)
		let decoded = try #require(LogLine(data: data))

		#expect(decoded.messageIdentifier == "63E1033A0")
		#expect(decoded.uniqueIdentifier == copy.uniqueIdentifier)
		#expect(decoded.messageBody == "hello")
	}

	@Test("A line with no message identifier decodes without one")
	func messageIdentifierIsOptional() throws {
		let line = LogLine()
		line.messageBody = "hello"

		let data = try NSKeyedArchiver.archivedData(withRootObject: line.duplicate(), requiringSecureCoding: true)
		let decoded = try #require(LogLine(data: data))

		#expect(decoded.messageIdentifier == nil)
	}

	@Test("A duplicate is a separate object carrying every value of the original")
	func duplicatePreservesCompleteValueState() {
		let receivedAt = Date(timeIntervalSince1970: 1_725_000_000)
		let line = LogLine()
		line.isEncrypted = true
		line.isFirstForDay = true
		line.receivedAt = receivedAt
		line.nickname = "alice"
		line.messageBody = "hello"
		line.command = "PRIVMSG"
		line.messageIdentifier = "message-id"
		line.replyToMessageIdentifier = "parent-id"
		line.reactions = ["👍": ["bob", "carol"]]
		line.lineType = .privateMessage
		line.memberType = .localUser
		line.deliveryState = .delivered
		line.highlightKeywords = ["hello"]
		line.excludeKeywords = ["ignore"]
		line.rendererAttributes = ["key": "value"]

		let copy = line.duplicate()

		#expect(copy !== line)
		#expect(copy.isEncrypted)
		#expect(copy.isFirstForDay)
		#expect(copy.receivedAt == receivedAt)
		#expect(copy.nickname == "alice")
		#expect(copy.messageBody == "hello")
		#expect(copy.command == "PRIVMSG")
		#expect(copy.messageIdentifier == "message-id")
		#expect(copy.replyToMessageIdentifier == "parent-id")
		#expect(copy.reactions == ["👍": ["bob", "carol"]])
		#expect(copy.lineType == .privateMessage)
		#expect(copy.memberType == .localUser)
		#expect(copy.deliveryState == .delivered)
		#expect(copy.highlightKeywords == ["hello"])
		#expect(copy.excludeKeywords == ["ignore"])
		#expect(copy.rendererAttributes?["key"] as? String == "value")
		#expect(copy.uniqueIdentifier == line.uniqueIdentifier)
		#expect(copy.sessionIdentifier == line.sessionIdentifier)
	}

	@Test("A pending delivery state is not carried out of the archive")
	func pendingDeliveryStateIsNotRestoredFromArchive() throws {
		let line = LogLine()
		line.deliveryState = .pending

		let data = try NSKeyedArchiver.archivedData(withRootObject: line.duplicate(), requiringSecureCoding: true)
		let decoded = try #require(LogLine(data: data))

		#expect(decoded.deliveryState == TVCLogLineDeliveryState.none)
		#expect(decoded.deliveryStateString == nil)
	}

	@Test("The renderer's names for the line and member types are the ones the templates read")
	func lineTypeAndMemberTypeStringsRetainRendererValues() {
		#expect(LogLine.string(for: .actionNoHighlight) == "action")
		#expect(LogLine.string(for: .ctcpReply) == "ctcp")
		#expect(LogLine.string(for: .dccFileTransfer) == "dcc-file-transfer")
		#expect(LogLine.string(for: .offTheRecordEncryptionStatus) == "off-the-record-encryption-status")
		#expect(LogLine.string(for: .privateMessageNoHighlight) == "privmsg")
		#expect(LogLine.string(for: .undefined) == nil)
		#expect(LogLine.string(for: .localUser) == "myself")
		#expect(LogLine.string(for: .normal) == "normal")
	}
}
