import CocoaExtensions
@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "GLTTestClient.h"
/// #import "ModeInfo.h"
/** *********************************************************************
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
@MainActor
final class ModeInfoTests: XCTestCase {
	func testConvenienceInitializers() {
		let unset = ModeInfo(modeSymbol: "n")
		let set = ModeInfo(modeSymbol: "t", modeIsSet: true)

		XCTAssertEqual(unset.modeSymbol, "n")
		XCTAssertFalse(unset.modeIsSet)
		XCTAssertNil(unset.modeParameter)
		XCTAssertEqual(set.modeSymbol, "t")
		XCTAssertTrue(set.modeIsSet)
	}

	func testMutableCopyCanChangeWithoutChangingOriginal() throws {
		let original = ModeInfo(modeSymbol: "k", modeIsSet: true, modeParameter: "secret")
		let changed = try XCTUnwrap(original.mutableCopy() as? MutableModeInfo)
		changed.modeIsSet = false
		changed.modeParameter = nil

		XCTAssertFalse(original.isMutable)
		XCTAssertTrue(changed.isMutable)
		XCTAssertTrue(original.modeIsSet)
		XCTAssertEqual(original.modeParameter, "secret")
		XCTAssertFalse(changed.modeIsSet)
		XCTAssertNil(changed.modeParameter)
	}

	func testUniqueCopyEntryPointsPreserveValuesAndRequestedMutability() throws {
		let original = ModeInfo(modeSymbol: "k", modeIsSet: true, modeParameter: "secret")
		let unique = try XCTUnwrap(original.uniqueCopy() as? ModeInfo)
		let uniqueMutable = try XCTUnwrap(original.uniqueCopyMutable() as? MutableModeInfo)

		XCTAssertFalse(unique === original)
		XCTAssertEqual(unique, original)
		XCTAssertFalse(unique.isMutable)
		XCTAssertTrue(uniqueMutable.isMutable)
		XCTAssertEqual(uniqueMutable, original)
	}

	func testEqualityAndHashUseAllFields() throws {
		let first = ModeInfo(modeSymbol: "k", modeIsSet: true, modeParameter: "secret")
		let second = try XCTUnwrap(first.mutableCopy() as? MutableModeInfo)

		XCTAssertEqual(first, second)
		XCTAssertEqual(first.hash, second.hash)

		second.modeParameter = "other"

		XCTAssertNotEqual(first, second)
	}

	func testMemberModeRequiresAParameterAndPrefixMode() {
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData("PREFIX=(ov)@+")

		let memberMode = ModeInfo(modeSymbol: "o", modeIsSet: true, modeParameter: "nick")
		let missingParameter = ModeInfo(modeSymbol: "o", modeIsSet: true)
		let channelMode = ModeInfo(modeSymbol: "n", modeIsSet: true, modeParameter: "nick")

		XCTAssertTrue(memberMode.isModeForChangingMemberMode(on: client))
		XCTAssertFalse(missingParameter.isModeForChangingMemberMode(on: client))
		XCTAssertFalse(channelMode.isModeForChangingMemberMode(on: client))
	}
}
