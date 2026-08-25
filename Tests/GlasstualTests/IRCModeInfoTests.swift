import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCISupportInfoPrivate.h"
// #import "IRCModeInfo.h"
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
class IRCModeInfoTests: XCTestCase {
    @objc
    func testConvenienceInitializers() {
        let unset: UnsafeMutablePointer<IRCModeInfo>! = IRCModeInfo(modeSymbol: "n")
        let set: UnsafeMutablePointer<IRCModeInfo>! = IRCModeInfo(modeSymbol: "t", modeIsSet: true)

        XCTAssertEqualObjects(unset.modeSymbol, "n")

        XCTAssertFalse(unset.modeIsSet)

        XCTAssertNil(unset.modeParameter)

        XCTAssertEqualObjects(set.modeSymbol, "t")

        XCTAssertTrue(set.modeIsSet)
    }
    @objc
    func testMutableCopyCanChangeWithoutChangingOriginal() {
        let original: UnsafeMutablePointer<IRCModeInfo>! = IRCModeInfo(modeSymbol: "k", modeIsSet: true, modeParameter: "secret")
        var changed: UnsafeMutablePointer<IRCModeInfoMutable>! = original.mutableCopy()

        changed.modeIsSet = false
        changed.modeParameter = nil

        XCTAssertFalse(original.mutable)

        XCTAssertTrue(changed.mutable)
        XCTAssertTrue(original.modeIsSet)

        XCTAssertEqualObjects(original.modeParameter, "secret")

        XCTAssertFalse(changed.modeIsSet)

        XCTAssertNil(changed.modeParameter)
    }
    @objc
    func testUniqueCopyEntryPointsPreserveValuesAndRequestedMutability() {
        let original: UnsafeMutablePointer<IRCModeInfo>! = IRCModeInfo(modeSymbol: "k", modeIsSet: true, modeParameter: "secret")
        let unique: UnsafeMutablePointer<IRCModeInfo>! = original.uniqueCopy()
        let uniqueMutable: UnsafeMutablePointer<IRCModeInfoMutable>! = original.uniqueCopyMutable()

        XCTAssertNotEqual(unique, original)

        XCTAssertEqualObjects(unique, original)

        XCTAssertFalse(unique.mutable)

        XCTAssertTrue(uniqueMutable.mutable)

        XCTAssertEqualObjects(uniqueMutable, original)
    }
    @objc
    func testEqualityAndHashUseAllFields() {
        let first: UnsafeMutablePointer<IRCModeInfo>! = IRCModeInfo(modeSymbol: "k", modeIsSet: true, modeParameter: "secret")
        var second: UnsafeMutablePointer<IRCModeInfoMutable>! = first.mutableCopy()

        XCTAssertEqualObjects(first, second)

        XCTAssertEqual(first.hash, second.hash)

        second.modeParameter = "other"

        XCTAssertNotEqualObjects(first, second)
    }
    @objc
    func testMemberModeRequiresAParameterAndPrefixMode() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()

        client.supportInfo.processConfigurationData("PREFIX=(ov)@+")

        let memberMode: UnsafeMutablePointer<IRCModeInfo>! = IRCModeInfo(modeSymbol: "o", modeIsSet: true, modeParameter: "nick")
        let missingParameter: UnsafeMutablePointer<IRCModeInfo>! = IRCModeInfo(modeSymbol: "o", modeIsSet: true)
        let channelMode: UnsafeMutablePointer<IRCModeInfo>! = IRCModeInfo(modeSymbol: "n", modeIsSet: true, modeParameter: "nick")

        XCTAssertTrue(memberMode.isModeForChangingMemberModeOn(client))
        XCTAssertFalse(missingParameter.isModeForChangingMemberModeOn(client))
        XCTAssertFalse(channelMode.isModeForChangingMemberModeOn(client))
    }
}