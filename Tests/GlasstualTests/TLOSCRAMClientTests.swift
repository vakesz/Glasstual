@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/** *********************************************************************
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
class TLOSCRAMClientTests: XCTestCase {
	private let serverFirst =
		"r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"

	private func exampleClient() -> SCRAMClient {
		SCRAMClient(username: "user", password: "pencil", clientNonce: "rOprNGfwEbeRWgbNEkqO")
	}

	func testClientFirstMessage() {
		let client = exampleClient()

		XCTAssertEqual(client.clientFirstMessage, "n,,n=user,r=rOprNGfwEbeRWgbNEkqO")
		XCTAssertEqual(client.state, .sentClientFirst)
	}

	func testClientFinalMessageMatchesRFC7677Vector() throws {
		let client = exampleClient()
		_ = client.clientFirstMessage

		let clientFinal = try client.clientFinalMessage(forServerFirstMessage: serverFirst)

		XCTAssertEqual(
			clientFinal,
			"c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ="
		)
	}

	func testVerifyServerFinalMessageSucceedsForCorrectSignature() throws {
		let client = exampleClient()
		_ = client.clientFirstMessage
		_ = try client.clientFinalMessage(forServerFirstMessage: serverFirst)

		try client.verifyServerFinalMessage("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")

		XCTAssertEqual(client.state, .authenticated)
	}

	func testVerifyServerFinalMessageRejectsWrongSignature() throws {
		let client = exampleClient()
		_ = client.clientFirstMessage
		_ = try client.clientFinalMessage(forServerFirstMessage: serverFirst)

		XCTAssertThrowsError(
			try client.verifyServerFinalMessage("v=7rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")
		) { error in
			XCTAssertEqual((error as NSError).code, SCRAMClientErrorCode.serverSignatureMismatch.rawValue)
		}
		XCTAssertEqual(client.state, .failed)
	}

	func testServerNonceMustBeginWithClientNonce() {
		assertFailure(
			for: "r=differentNonce,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096",
			code: .nonceMismatch
		)
	}

	func testIterationCountBelowMinimumIsRejected() {
		assertFailure(
			for: "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=1024",
			code: .iterationCountTooLow
		)
	}

	func testMalformedServerFirstMessageIsRejected() {
		assertFailure(for: "nonsense", code: .malformedServerMessage)
	}

	private func assertFailure(
		for serverMessage: String,
		code: SCRAMClientErrorCode,
		file: StaticString = #filePath,
		line: UInt = #line
	) {
		let client = exampleClient()
		_ = client.clientFirstMessage

		XCTAssertThrowsError(
			try client.clientFinalMessage(forServerFirstMessage: serverMessage),
			file: file,
			line: line
		) { error in
			XCTAssertEqual((error as NSError).code, code.rawValue, file: file, line: line)
		}
	}
}
