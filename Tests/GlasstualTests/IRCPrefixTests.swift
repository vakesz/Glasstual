@testable import Glasstual
import XCTest

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
class IRCPrefixTests: XCTestCase {
	func testDefaultsAreNonnullableEmptyStrings() {
		let prefix = IRCPrefix()

		XCTAssertFalse(prefix.isServer)

		XCTAssertEqual(prefix.nickname, "")
		XCTAssertEqual(prefix.hostmask, "")

		XCTAssertNil(prefix.username)
		XCTAssertNil(prefix.address)
	}

	func testMutableCopyCanChangeWithoutChangingOriginal() throws {
		var source = IRCPrefixMutable()

		source.isServer = true
		source.nickname = "nick"
		source.username = "user"
		source.address = "host"
		source.hostmask = "nick!user@host"

		let immutable = try XCTUnwrap(source.copy() as? IRCPrefix)
		let changed = try XCTUnwrap(immutable.mutableCopy() as? IRCPrefixMutable)

		changed.nickname = "other"

		XCTAssertTrue(source.isMutable)

		XCTAssertFalse(immutable.isMutable)

		XCTAssertTrue(changed.isMutable)

		XCTAssertEqual(immutable.nickname, "nick")
		XCTAssertEqual(changed.nickname, "other")
		XCTAssertEqual(changed.username, "user")
		XCTAssertEqual(changed.address, "host")
		XCTAssertEqual(changed.hostmask, "nick!user@host")
	}

	func testUniqueCopyEntryPointsPreserveValuesAndRequestedMutability() throws {
		var source = IRCPrefixMutable()

		source.nickname = "nick"
		source.hostmask = "nick!user@host"

		let immutable = try XCTUnwrap(source.copy() as? IRCPrefix)
		let unique = try XCTUnwrap(immutable.uniqueCopy() as? IRCPrefix)
		let uniqueMutable = try XCTUnwrap(immutable.uniqueCopyMutable() as? IRCPrefixMutable)

		XCTAssertFalse(unique === immutable)

		XCTAssertEqual(unique, immutable)

		XCTAssertFalse(unique.isMutable)

		XCTAssertTrue(uniqueMutable.isMutable)

		XCTAssertEqual(uniqueMutable, immutable)
	}

	func testImmutableCopyReturnsSameObject() throws {
		var mutable = IRCPrefixMutable()

		mutable.nickname = "nick"

		let immutable = try XCTUnwrap(mutable.copy() as? IRCPrefix)

		XCTAssertEqual(immutable.copy() as? IRCPrefix, immutable)
	}

	func testEqualityAndHashUseAllFields() throws {
		var first = IRCPrefixMutable()

		first.nickname = "nick"
		first.username = "user"
		first.address = "host"
		first.hostmask = "nick!user@host"

		let second = try XCTUnwrap(first.mutableCopy() as? IRCPrefixMutable)

		XCTAssertEqual(first, second)

		XCTAssertEqual(first.hash, second.hash)

		second.isServer = true

		XCTAssertNotEqual(first, second)
	}
}
