import Foundation
@testable import Glasstual
import XCTest

/** *********************************************************************
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
@MainActor
class TVCLogLineTests: XCTestCase {
	func testMessageIdentifierSurvivesArchivingAndCopying() throws {
		let line = LogLine()
		line.command = "privmsg"
		line.lineType = .privateMessage
		line.nickname = "alice"
		line.messageBody = "hello"
		line.messageIdentifier = "63E1033A0"

		let copy = line.duplicate()
		XCTAssertEqual(copy.messageIdentifier, "63E1033A0")

		let data = try NSKeyedArchiver.archivedData(withRootObject: copy, requiringSecureCoding: true)
		let decoded = try XCTUnwrap(LogLine(data: data))

		XCTAssertEqual(decoded.messageIdentifier, "63E1033A0")
		XCTAssertEqual(decoded.uniqueIdentifier, copy.uniqueIdentifier)
		XCTAssertEqual(decoded.messageBody, "hello")
	}

	func testMessageIdentifierIsOptional() throws {
		let line = LogLine()
		line.messageBody = "hello"

		let data = try NSKeyedArchiver.archivedData(withRootObject: line.duplicate(), requiringSecureCoding: true)
		let decoded = try XCTUnwrap(LogLine(data: data))

		XCTAssertNil(decoded.messageIdentifier)
	}

	func testDuplicatePreservesCompleteValueState() {
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

		XCTAssertFalse(copy === line)
		XCTAssertTrue(copy.isEncrypted)
		XCTAssertTrue(copy.isFirstForDay)
		XCTAssertEqual(copy.receivedAt, receivedAt)
		XCTAssertEqual(copy.nickname, "alice")
		XCTAssertEqual(copy.messageBody, "hello")
		XCTAssertEqual(copy.command, "PRIVMSG")
		XCTAssertEqual(copy.messageIdentifier, "message-id")
		XCTAssertEqual(copy.replyToMessageIdentifier, "parent-id")
		XCTAssertEqual(copy.reactions, ["👍": ["bob", "carol"]])
		XCTAssertEqual(copy.lineType, .privateMessage)
		XCTAssertEqual(copy.memberType, .localUser)
		XCTAssertEqual(copy.deliveryState, .delivered)
		XCTAssertEqual(copy.highlightKeywords, ["hello"])
		XCTAssertEqual(copy.excludeKeywords, ["ignore"])
		XCTAssertEqual(copy.rendererAttributes?["key"] as? String, "value")
		XCTAssertEqual(copy.uniqueIdentifier, line.uniqueIdentifier)
		XCTAssertEqual(copy.sessionIdentifier, line.sessionIdentifier)
	}

	func testPendingDeliveryStateIsNotRestoredFromArchive() throws {
		let line = LogLine()
		line.deliveryState = .pending

		let data = try NSKeyedArchiver.archivedData(withRootObject: line.duplicate(), requiringSecureCoding: true)
		let decoded = try XCTUnwrap(LogLine(data: data))

		XCTAssertEqual(decoded.deliveryState, .none)
		XCTAssertNil(decoded.deliveryStateString)
	}

	func testLineTypeAndMemberTypeStringsRetainRendererValues() {
		XCTAssertEqual(LogLine.string(for: .actionNoHighlight), "action")
		XCTAssertEqual(LogLine.string(for: .ctcpReply), "ctcp")
		XCTAssertEqual(LogLine.string(for: .dccFileTransfer), "dcc-file-transfer")
		XCTAssertEqual(LogLine.string(for: .offTheRecordEncryptionStatus), "off-the-record-encryption-status")
		XCTAssertEqual(LogLine.string(for: .privateMessageNoHighlight), "privmsg")
		XCTAssertNil(LogLine.string(for: .undefined))
		XCTAssertEqual(LogLine.string(for: .localUser), "myself")
		XCTAssertEqual(LogLine.string(for: .normal), "normal")
	}
}
