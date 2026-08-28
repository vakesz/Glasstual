/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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

@testable import Glasstual
import XCTest

@MainActor
final class IRCClientDCCPolicyTests: XCTestCase {
	func testParsesQuotedSendAndNormalizesToken() {
		let request = DCCFileTransferRequestParser.parse("SEND \"hello world.txt\" 3232235777 0 42 T123")
		XCTAssertEqual(
			request,
			.send(filename: "hello world.txt", address: "192.168.1.1", port: 0, filesize: 42, token: "123")
		)
	}

	func testRejectsInvalidFileTransferRanges() {
		XCTAssertNil(DCCFileTransferRequestParser.parse("SEND file 3232235777 0 42"))
		XCTAssertNil(DCCFileTransferRequestParser.parse("SEND file 3232235777 65536 42"))
		XCTAssertNil(DCCFileTransferRequestParser.parse("SEND file 3232235777 5000 0"))
		XCTAssertNil(DCCFileTransferRequestParser.parse("RESUME file 5000 12 token"))
	}

	func testFormatsResumeAndSendArguments() {
		XCTAssertEqual(
			DCCFileTransferRequestParser.transferArguments(
				filename: "hello world.txt", port: 5000, position: 12, token: "7"
			),
			"\"hello world.txt\" 5000 12 7"
		)
		XCTAssertEqual(
			DCCFileTransferRequestParser.sendArguments(
				filename: "file.txt", address: "42", port: 5000, filesize: 99, token: nil
			),
			"file.txt 42 5000 99"
		)
	}

	func testParsesActiveAndPassiveChatOffers() {
		XCTAssertEqual(
			DCCChatPolicy.parseOffer("CHAT chat 3232235777 5000"),
			DCCChatOffer(address: "192.168.1.1", port: 5000, token: nil)
		)
		XCTAssertEqual(
			DCCChatPolicy.parseOffer("CHAT chat 0 0 T99"),
			DCCChatOffer(address: "0.0.0.0", port: 0, token: "99")
		)
		XCTAssertNil(DCCChatPolicy.parseOffer("CHAT chat invalid 5000"))
		XCTAssertNil(DCCChatPolicy.parseOffer("CHAT chat 3232235777 0"))
	}

	func testDirectChatWireNames() {
		XCTAssertEqual(DCCChatPolicy.channelName(for: "alice"), "=alice")
		XCTAssertEqual(
			DCCChatPolicy.listeningArguments(address: "42", port: 5000, token: "9"),
			"chat 42 5000 9"
		)
	}
}
