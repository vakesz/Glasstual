import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "IRCMessage.h"
// #import "IRCSendingMessage.h"
// #import "NSStringHelper.h"
/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
@objc
class IRCSendingMessageTests: XCTestCase {
    @objc
    func testCommandWithoutTagsIsUnchanged() {
        let line: String! = IRCSendingMessage.stringWithCommand("privmsg", arguments: ["#c", "hello world"], tags: nil)

        XCTAssertEqualObjects(line, "PRIVMSG #c :hello world")

        let lineWithEmptyTags: String! = IRCSendingMessage.stringWithCommand("PRIVMSG", arguments: ["#c", "hi"], tags: [:])

        XCTAssertEqualObjects(lineWithEmptyTags, "PRIVMSG #c :hi")
    }
    @objc
    func testTagsAreSerializedSortedAndEscaped() {
        let tags: NSDictionary = ["+typing": "active", "+draft/reply": "a b;c\\\\d\\r\\n", "flag": ""]

        XCTAssertEqualObjects(IRCSendingMessage.stringWithMessageTags(tags), "+draft/reply=a\\\\sb\\\\:c\\\\\\\\d\\\\r\\\\n;+typing=active;flag")

        let line: String! = IRCSendingMessage.stringWithCommand("TAGMSG", arguments: ["#c"], tags: tags)

        XCTAssertEqualObjects(line, "@+draft/reply=a\\\\sb\\\\:c\\\\\\\\d\\\\r\\\\n;+typing=active;flag TAGMSG #c")
    }
    @objc
    func testTagEscapingRoundTrips() {
        let tags: NSDictionary = ["a": "plain", "b": "semi;colon", "c": "with space", "d": "back\\\\slash", "e": "line\\r\\nbreak", "f": "trailing\\\\", "g": "unicode ✓", "h": ""]
        let line: String! = IRCSendingMessage.stringWithCommand("TAGMSG", arguments: ["#c"], tags: tags)
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: line)

        XCTAssertNotNil(message)
        XCTAssertEqualObjects(message.command, "TAGMSG")
        XCTAssertEqualObjects(message.messageTags, tags)
    }
    @objc
    func testEncodeDecodeHelpersRoundTripEveryEscape() {
        let value = "a;b \\r\\n\\\\s\\\\:end\\\\"

        XCTAssertEqualObjects(value.encodedMessageTagString.decodedMessageTagString, value)
    }
}