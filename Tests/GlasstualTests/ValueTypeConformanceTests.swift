/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

import Foundation
@testable import Glasstual
import Testing

/** The configuration values the plan calls for as `Codable, Sendable` structs.

 `Sendable` was implicit — inferred for these types inside the module and
 nowhere written down — so nothing stopped a later field of reference type from
 quietly withdrawing it. Stating the conformance makes the compiler check it. */
struct ValueTypeConformanceTests {
	/// A generic function only accepts what actually conforms, so this fails to
	/// compile rather than to run if a conformance is lost.
	private func requireSendable(_: some Sendable) {}

	private func requireCodable(_: some Codable) {}

	@MainActor
	@Test("The client configuration is a Sendable, Codable value")
	func clientConfigConforms() {
		let config = ClientConfig()

		requireSendable(config)
		requireCodable(config)
	}

	@Test("An address book entry is a Sendable, Codable value")
	func addressBookEntryConforms() {
		let entry = AddressBookEntry(entryType: .ignore)

		requireSendable(entry)
		requireCodable(entry)
	}

	@Test("A highlight log entry survives a Codable round trip")
	func highlightLogEntryRoundTrips() throws {
		var line = LogLine()

		line.messageBody = "someone said your name"
		line.nickname = "mara"
		line.lineType = .privateMessage

		let entry = HighlightLogEntry(lineLogged: line, clientId: "c1", channelId: "ch1")
		let encoded = try JSONEncoder().encode(entry)
		let decoded = try JSONDecoder().decode(HighlightLogEntry.self, from: encoded)

		#expect(decoded == entry)
		#expect(decoded.lineLogged.messageBody == "someone said your name")
		#expect(decoded.lineLogged.nickname == "mara")
		#expect(decoded.lineLogged.lineType == .privateMessage)
		#expect(decoded.lineNumber == entry.lineNumber)
	}
}
