import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCChannelModePrivate.h"
// #import "IRCChannelPrivate.h"
// #import "IRCISupportInfoPrivate.h"
// #import "IRCTreeItemPrivate.h"
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
class IRCChannelModeTests: XCTestCase {
    @objc
    func channelModeWithCurrentModes(_ modeString: String) -> UnsafeMutablePointer<IRCChannelMode> {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()

        client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")

        var channel: UnsafeMutablePointer<IRCChannel>! = IRCChannel(configDictionary: ["channelName": "#chat"])

        channel.associatedClient = client

        let channelMode: UnsafeMutablePointer<IRCChannelMode>! = IRCChannelMode(channel: channel)

        channelMode.updateModes(modeString)

        return channelMode
    }
    @objc
    func testRemovedModeParametersPrecedeAddedOnes() {
        let channelMode = self.channelModeWithCurrentModes("+nk secret")
        let modes: UnsafeMutablePointer<IRCChannelModeContainer>! = channelMode.modes.copy()

        modes.changeMode("k", modeIsSet: false, modeParameter: "secret")
        modes.changeMode("l", modeIsSet: true, modeParameter: "10")
        /* "-k+l secret 10": the server consumes parameters in the order
	 the letters appear. */
        XCTAssertEqualObjects(channelMode.getChangeCommand(modes), "-k+l secret 10")
    }
    @objc
    func testUnchangedModesProduceNoCommand() {
        let channelMode = self.channelModeWithCurrentModes("+nt")

        XCTAssertEqualObjects(channelMode.getChangeCommand(channelMode.modes.copy()), "")
    }
    @objc
    func testModeStringListsParametersAfterLetters() {
        let channelMode = self.channelModeWithCurrentModes("+ntk secret +l 5")

        XCTAssertEqualObjects(channelMode.string, "+klnt secret 5")
        XCTAssertEqualObjects(channelMode.stringWithMaskedPassword, "+klnt ****** 5")
    }
    @objc
    func testChangeCommandIsDeterministic() {
        let channelMode = self.channelModeWithCurrentModes("")
        let modes: UnsafeMutablePointer<IRCChannelModeContainer>! = channelMode.modes.copy()

        modes.changeMode("z", modeIsSet: true, modeParameter: "last")
        modes.changeMode("a", modeIsSet: true, modeParameter: "first")
        XCTAssertEqualObjects(channelMode.getChangeCommand(modes), "+az first last")
    }
    @objc
    func testListAndUserModesAreNotStoredAsChannelState() {
        let channelMode = self.channelModeWithCurrentModes("")

        XCTAssertNil(channelMode.modeInfoFor("b"))
        XCTAssertNil(channelMode.modeInfoFor("o"))
        XCTAssertNotNil(channelMode.modeInfoFor("n"))
    }
    @objc
    func testCopiedContainerHasIndependentState() {
        let channelMode = self.channelModeWithCurrentModes("+nt")
        let modes: UnsafeMutablePointer<IRCChannelModeContainer>! = channelMode.modes.copy()

        modes.changeMode("k", modeIsSet: true, modeParameter: "secret")

        XCTAssertFalse(channelMode.modeIsDefined("k"))

        XCTAssertTrue(modes.modeIsDefined("k"))

        modes.clear()

        XCTAssertTrue(channelMode.modeIsDefined("n"))

        XCTAssertEqual(modes.modes.count, 0)
    }
}