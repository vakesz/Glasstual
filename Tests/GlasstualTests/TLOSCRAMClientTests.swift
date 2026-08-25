import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "TLOSCRAMClient.h"
/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
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
class TLOSCRAMClientTests: XCTestCase {
    /* RFC 7677 section 3 worked example: user "user", password "pencil",
 client nonce "rOprNGfwEbeRWgbNEkqO". */
    @objc
    func exampleClient() -> UnsafeMutablePointer<TLOSCRAMClient> {
        return TLOSCRAMClient(username: "user", password: "pencil", clientNonce: "rOprNGfwEbeRWgbNEkqO")
    }
    @objc
    func testClientFirstMessage() {
        let client = self.exampleClient()

        XCTAssertEqualObjects(client.clientFirstMessage, "n,,n=user,r=rOprNGfwEbeRWgbNEkqO")
        XCTAssertEqual(client.state, TLOSCRAMClientStateSentClientFirst)
    }
    @objc
    func testClientFinalMessageMatchesRFC7677Vector() {
        let client = self.exampleClient()

        client.clientFirstMessage as? Void

        let serverFirst = "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
        var error: Error! = nil
        let clientFinal: String! = client.clientFinalMessageForServerFirstMessage(serverFirst, error: &error)

        XCTAssertNil(error)
        XCTAssertEqualObjects(clientFinal, "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=")
    }
    @objc
    func testVerifyServerFinalMessageSucceedsForCorrectSignature() {
        let client = self.exampleClient()

        client.clientFirstMessage as? Void

        var error: Error! = nil

        client.clientFinalMessageForServerFirstMessage("r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096", error: &error)

        let verified: Bool = client.verifyServerFinalMessage("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=", error: &error)

        XCTAssertTrue(verified)
        XCTAssertNil(error)
        XCTAssertEqual(client.state, TLOSCRAMClientStateAuthenticated)
    }
    @objc
    func testVerifyServerFinalMessageRejectsWrongSignature() {
        let client = self.exampleClient()

        client.clientFirstMessage as? Void

        var error: Error! = nil

        client.clientFinalMessageForServerFirstMessage("r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096", error: &error)

        /* A single flipped character must be rejected. */
        let verified: Bool = client.verifyServerFinalMessage("v=7rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=", error: &error)

        XCTAssertFalse(verified)
        XCTAssertEqual(error?.code, TLOSCRAMClientErrorCodeServerSignatureMismatch)
        XCTAssertEqual(client.state, TLOSCRAMClientStateFailed)
    }
    @objc
    func testServerNonceMustBeginWithClientNonce() {
        let client = self.exampleClient()

        client.clientFirstMessage as? Void

        var error: Error! = nil
        let clientFinal: String! = client.clientFinalMessageForServerFirstMessage("r=differentNonce,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096", error: &error)

        XCTAssertNil(clientFinal)
        XCTAssertEqual(error?.code, TLOSCRAMClientErrorCodeNonceMismatch)
    }
    @objc
    func testIterationCountBelowMinimumIsRejected() {
        let client = self.exampleClient()

        client.clientFirstMessage as? Void

        var error: Error! = nil
        let clientFinal: String! = client.clientFinalMessageForServerFirstMessage("r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=1024", error: &error)

        XCTAssertNil(clientFinal)
        XCTAssertEqual(error?.code, TLOSCRAMClientErrorCodeIterationCountTooLow)
    }
    @objc
    func testMalformedServerFirstMessageIsRejected() {
        let client = self.exampleClient()

        client.clientFirstMessage as? Void

        var error: Error! = nil
        let clientFinal: String! = client.clientFinalMessageForServerFirstMessage("nonsense", error: &error)

        XCTAssertNil(clientFinal)
        XCTAssertEqual(error?.code, TLOSCRAMClientErrorCodeMalformedServerMessage)
    }
}