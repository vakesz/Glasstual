/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

/// Behaviour corpus for the command catalog.
///
/// The property lists and the `IRCLocalCommand` / `IRCRemoteCommand` enums are
/// two copies of the same table. These tests pin them to each other so a
/// command added to one is not forgotten in the other.
@MainActor
struct IRCCommandIndexCorpusTests {
	private static let reservedKey = "Reserved Information"

	/// Index values of every command in a command-index property list.
	private static func indexes(inResource name: String) throws -> Set<UInt> {
		let values = try #require(ResourceManager.dictionary(fromResources: name, cacheValue: false))
		var indexes: Set<UInt> = []

		for (key, value) in values where key != reservedKey {
			let entry = try #require(value as? [String: Any], "\(name): \(key) is not a dictionary")
			let index = try #require((entry["indexValue"] as? NSNumber)?.uintValue, "\(name): \(key) has no index")

			indexes.insert(index)
		}

		return indexes
	}

	/// Raw values the enum accepts, discovered by probing the band the
	/// catalog reserves for it.
	private static func rawValues(in range: ClosedRange<UInt>, isLocal: Bool) -> Set<UInt> {
		var rawValues: Set<UInt> = []

		for candidate in range {
			let known =
				isLocal
					? IRCLocalCommand(rawValue: candidate) != nil
					: IRCRemoteCommand(rawValue: candidate) != nil

			if known {
				rawValues.insert(candidate)
			}
		}

		return rawValues
	}

	@Test
	func localCommandsAndTheirEnumAgreeInBothDirections() throws {
		let plistIndexes = try Self.indexes(inResource: "IRCCommandIndexLocalData")
		let enumIndexes = Self.rawValues(in: 5000 ... 5999, isLocal: true)

		#expect(plistIndexes.isEmpty == false)
		#expect(plistIndexes.subtracting(enumIndexes).isEmpty, "commands in the plist with no IRCLocalCommand case")
		#expect(enumIndexes.subtracting(plistIndexes).isEmpty, "IRCLocalCommand cases with no plist entry")
	}

	@Test
	func remoteCommandsInThePlistAllHaveAnEnumCase() throws {
		let plistIndexes = try Self.indexes(inResource: "IRCCommandIndexRemoteData")
		let enumIndexes = Self.rawValues(in: 1000 ... 1999, isLocal: false)

		#expect(plistIndexes.isEmpty == false)
		#expect(plistIndexes.subtracting(enumIndexes).isEmpty, "commands in the plist with no IRCRemoteCommand case")

		/* Two cases are synthesised by the client rather than sent by a
		 server, so they carry no property list entry. */
		#expect(
			enumIndexes.subtracting(plistIndexes) == [
				IRCRemoteCommand.privmsgAction.rawValue,
				IRCRemoteCommand.time.rawValue,
			]
		)
	}

	@Test
	func everyLocalCommandNameResolvesToItsIndex() throws {
		CommandIndex.populateCommandIndex()

		let values = try #require(
			ResourceManager.dictionary(fromResources: "IRCCommandIndexLocalData", cacheValue: false)
		)

		for (name, value) in values where name != Self.reservedKey {
			let entry = try #require(value as? [String: Any])
			let index = try #require((entry["indexValue"] as? NSNumber)?.uintValue)
			let developerOnly = (entry["developerModeOnly"] as? NSNumber)?.boolValue ?? false
			let resolved = CommandIndex.index(ofLocalCommand: name)

			if developerOnly {
				/* Hidden unless the user turned developer mode on. */
				#expect(resolved == UInt(NSNotFound), "\(name)")
			} else {
				#expect(resolved == index, "\(name)")
				#expect(CommandIndex.index(ofLocalCommand: name.uppercased()) == index, "\(name)")
			}
		}
	}

	@Test
	func everyRemoteCommandNameResolvesToItsIndex() throws {
		CommandIndex.populateCommandIndex()

		let values = try #require(
			ResourceManager.dictionary(fromResources: "IRCCommandIndexRemoteData", cacheValue: false)
		)

		for (name, value) in values where name != Self.reservedKey {
			let entry = try #require(value as? [String: Any])
			let index = try #require((entry["indexValue"] as? NSNumber)?.uintValue)

			#expect(CommandIndex.index(ofRemoteCommand: name) == index, "\(name)")
			#expect(CommandIndex.index(ofRemoteCommand: name.uppercased()) == index, "\(name)")
		}
	}

	/// The developer-mode commands are hidden from the completion list too.
	@Test(arguments: ["recv", "tage", "join_random"])
	func developerCommandsAreHiddenByDefault(name: String) {
		CommandIndex.populateCommandIndex()

		#expect(CommandIndex.index(ofLocalCommand: name) == UInt(NSNotFound))
		#expect(CommandIndex.localCommandList().contains(name.uppercased()) == false)
	}

	@Test
	func unknownCommandsAreNotFound() {
		CommandIndex.populateCommandIndex()

		#expect(CommandIndex.index(ofLocalCommand: "not-a-command") == UInt(NSNotFound))
		#expect(CommandIndex.index(ofRemoteCommand: "not-a-command") == UInt(NSNotFound))
		#expect(CommandIndex.colonPosition(forRemoteCommand: "not-a-command") == UInt(NSNotFound))
		#expect(CommandIndex.syntax(forLocalCommand: "not-a-command") == nil)
	}

	@Test
	func reservedInformationIsNotACommand() {
		CommandIndex.populateCommandIndex()

		#expect(CommandIndex.index(ofLocalCommand: Self.reservedKey) == UInt(NSNotFound))
		#expect(CommandIndex.localCommandList().contains(Self.reservedKey) == false)
	}

	// MARK: - Outgoing colon positions

	struct ColonCase: Sendable {
		let command: String
		let position: UInt

		init(_ command: String, _ position: UInt) {
			self.command = command
			self.position = position
		}
	}

	/// The colon marks the start of the trailing parameter. `notApplicable`
	/// stands for commands that never take one.
	nonisolated static let colonCases: [ColonCase] = [
		ColonCase("PRIVMSG", 1),
		ColonCase("NOTICE", 1),
		ColonCase("PART", 1),
		ColonCase("TOPIC", 1),
		ColonCase("KILL", 1),
		ColonCase("TEMPSHUN", 1),
		ColonCase("KICK", 2),
		ColonCase("FAIL", 2),
		ColonCase("WARN", 2),
		ColonCase("NOTE", 2),
		ColonCase("GLINE", 2),
		ColonCase("ZLINE", 2),
		ColonCase("SHUN", 2),
		ColonCase("USER", 3),
		ColonCase("AWAY", 0),
		ColonCase("QUIT", 0),
		ColonCase("ERROR", 0),
		ColonCase("WALLOPS", 0),
		ColonCase("SETNAME", 0),
		/* PASS must never gain a trailing marker. */
		ColonCase("PASS", UInt(NSNotFound)),
	]

	@Test(arguments: Self.colonCases)
	func readsOutgoingColonPositions(testCase: ColonCase) {
		CommandIndex.populateCommandIndex()

		#expect(CommandIndex.colonPosition(forRemoteCommand: testCase.command) == testCase.position)
		#expect(CommandIndex.colonPosition(forRemoteCommand: testCase.command.lowercased()) == testCase.position)
	}

	/// A colon position of 999 is the catalog's "no trailing parameter"
	/// sentinel: it is a real position, so it is never reported as not found,
	/// but no command carries that many parameters.
	@Test(arguments: ["JOIN", "MODE", "WHO", "WHOIS", "PING", "PONG", "CAP", "AUTHENTICATE"])
	func commandsWithoutATrailingParameterUseTheSentinel(command: String) {
		CommandIndex.populateCommandIndex()

		#expect(CommandIndex.colonPosition(forRemoteCommand: command) == 999)
	}

	@Test
	func colonPositionDrivesTheOutgoingLine() {
		CommandIndex.populateCommandIndex()

		#expect(
			SendingMessage.string(command: "PRIVMSG", arguments: ["#chat", "hello there"])
				== "PRIVMSG #chat :hello there"
		)
		#expect(
			SendingMessage.string(command: "KICK", arguments: ["#chat", "alice", "bye now"])
				== "KICK #chat alice :bye now"
		)
		/* PASS never gets a colon, even for a value containing a space. */
		#expect(SendingMessage.string(command: "PASS", arguments: ["a b"]) == "PASS :a b")
		#expect(SendingMessage.string(command: "JOIN", arguments: ["#chat"]) == "JOIN #chat")
	}

	// MARK: - Syntax strings

	@Test(arguments: ["away", "back", "join", "kick", "topic"])
	func localCommandsExposeASyntaxString(command: String) throws {
		CommandIndex.populateCommandIndex()

		let syntax = try #require(CommandIndex.syntax(forLocalCommand: command))

		#expect(syntax.hasPrefix(command.uppercased()))
	}
}
