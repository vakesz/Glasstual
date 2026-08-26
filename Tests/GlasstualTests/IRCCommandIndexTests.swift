@testable import Glasstual
import XCTest

/** *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
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
@objc
class IRCCommandIndexTests: XCTestCase {
	@objc
	override static func setUp() {
		super.setUp()
		CommandIndex.populateCommandIndex()
	}

	@objc
	func testCommandIndexesAreCaseInsensitive() {
		XCTAssertEqual(CommandIndex.index(ofRemoteCommand: "privmsg"), 1035)
		XCTAssertEqual(CommandIndex.index(ofRemoteCommand: "PRIVMSG"), 1035)
		XCTAssertEqual(CommandIndex.index(ofLocalCommand: "join"), 5032)
		XCTAssertEqual(CommandIndex.index(ofLocalCommand: "JOIN"), 5032)
	}

	@objc
	func testUnknownCommandsReturnNotFound() {
		XCTAssertEqual(CommandIndex.index(ofRemoteCommand: "not-a-command"), UInt(NSNotFound))
		XCTAssertEqual(CommandIndex.index(ofLocalCommand: "not-a-command"), UInt(NSNotFound))
		XCTAssertEqual(CommandIndex.colonPosition(forRemoteCommand: "not-a-command"), UInt(NSNotFound))
	}

	@objc
	func testOutgoingColonPositionsComeFromRemoteCommandMetadata() {
		XCTAssertEqual(CommandIndex.colonPosition(forRemoteCommand: "PRIVMSG"), 1)
		XCTAssertEqual(CommandIndex.colonPosition(forRemoteCommand: "FAIL"), 2)
		XCTAssertEqual(CommandIndex.colonPosition(forRemoteCommand: "PASS"), UInt(NSNotFound))
	}

	@objc
	func testLocalCommandSyntaxAndCompletionList() {
		XCTAssertEqual(CommandIndex.syntax(forLocalCommand: "away"), "AWAY [comment]")
		XCTAssertEqual(CommandIndex.syntax(forLocalCommand: "back"), "BACK")
		XCTAssertNil(CommandIndex.syntax(forLocalCommand: "not-a-command"))

		let commands: [String]! = CommandIndex.localCommandList()

		XCTAssertTrue(commands.contains("JOIN"))
		XCTAssertFalse(commands.contains("Reserved Information"))
	}
}
