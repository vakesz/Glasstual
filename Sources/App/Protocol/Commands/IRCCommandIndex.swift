/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

import CocoaExtensions
import Foundation

public final class CommandIndex: NSObject {
	public static func populateCommandIndex() {
		/* Reading the tables is what builds them, and Swift guarantees that
		 happens exactly once. Called at start-up so the first command does not
		 pay for it. */
		_ = commandIndexTables.isEmpty
	}

	public static func invalidateCaches() {
		/* Nothing left to invalidate: the developer-mode split is decided when
		 the tables are built, so both command lists already exist. Kept because
		 the preference reload still calls it. */
	}

	public static func localCommandList() -> [String] {
		commandIndexTables.commandNames(developerModeEnabled: Preferences.Commands.developerMode.value)
	}

	public static func index(ofRemoteCommand command: String) -> UInt {
		commandIndexTables.remote[command.lowercased()]?.index ?? CommandIndexTables.notFound
	}

	public static func index(ofLocalCommand command: String) -> UInt {
		guard let entry = commandIndexTables.local[command.lowercased()] else {
			return CommandIndexTables.notFound
		}

		if entry.isDeveloperModeOnly, Preferences.Commands.developerMode.value == false {
			return CommandIndexTables.notFound
		}

		return entry.index
	}

	public static func colonPosition(forRemoteCommand command: String) -> UInt {
		guard let entry = commandIndexTables.remote[command.lowercased()],
		      entry.outgoingColonIndex >= 0
		else {
			return CommandIndexTables.notFound
		}

		return UInt(entry.outgoingColonIndex)
	}

	public static func syntax(forLocalCommand command: String) -> String? {
		guard let entry = commandIndexTables.local[command.lowercased()] else {
			return nil
		}

		let name = command.uppercased()

		guard let arguments = entry.arguments else {
			return name
		}

		return "\(name) \(arguments)"
	}

	/// Everything the index knows about one local command, or `nil` when the
	/// name is not in the index. Unlike `index(ofLocalCommand:)` this does not
	/// hide developer-mode commands: it reports the flag, so the dispatcher can
	/// refuse such a command with a message instead of mistaking it for one it
	/// has never heard of and forwarding it to the server.
	public static func descriptor(forLocalCommand command: String) -> LocalCommandDescriptor? {
		guard let entry = commandIndexTables.local[command.lowercased()],
		      let value = IRCLocalCommand(rawValue: entry.index)
		else {
			return nil
		}

		return LocalCommandDescriptor(
			command: value,
			isDeveloperModeOnly: entry.isDeveloperModeOnly,
			arity: CommandArity(syntax: entry.arguments)
		)
	}
}

/// How many argument groups a command's index entry declares.
///
/// Counted from the syntax string the index carries: every top-level `<group>`
/// is required and every `[group]` is optional. It describes the documented
/// syntax, not what a particular handler goes on to read.
public nonisolated struct CommandArity: Sendable, Equatable { // nonisolated: value
	public let required: Int
	public let optional: Int

	public static let none = CommandArity(required: 0, optional: 0)

	public init(required: Int, optional: Int) {
		self.required = required
		self.optional = optional
	}

	public init(syntax: String?) {
		guard let syntax else {
			self = .none

			return
		}

		var required = 0
		var optional = 0
		var depth = 0
		var openedWith: Character?

		for character in syntax {
			switch character {
			case "<", "[":
				if depth == 0 {
					openedWith = character
				}

				depth += 1
			case ">", "]":
				guard depth > 0 else {
					continue
				}

				depth -= 1

				if depth == 0 {
					if openedWith == "<" {
						required += 1
					} else {
						optional += 1
					}
				}
			default:
				continue
			}
		}

		self.init(required: required, optional: optional)
	}
}

/// What the command index knows about one local command.
public nonisolated struct LocalCommandDescriptor: Sendable { // nonisolated: value
	public let command: IRCLocalCommand

	/// The command is kept out of completion and refused unless the
	/// developer-mode preference is on.
	public let isDeveloperModeOnly: Bool

	public let arity: CommandArity
}

/** Built once, lazily, by Swift's own global initialisation -- the lifecycle the
 old storage hand-rolled behind a lock. */
private nonisolated let commandIndexTables = CommandIndexTables.loaded() // nonisolated: let

/// The command tables, parsed once from the bundled index resources.
///
/// Everything an entry says is settled when the table is built, so the whole
/// thing is an immutable value that any isolation domain can read. That is what
/// replaced the lock: there is nothing left to synchronise.
nonisolated struct CommandIndexTables: Sendable { // nonisolated: value
	struct LocalEntry: Sendable {
		let index: UInt
		let isDeveloperModeOnly: Bool
		let arguments: String?
	}

	struct RemoteEntry: Sendable {
		let index: UInt
		let outgoingColonIndex: Int
	}

	static let notFound = UInt(NSNotFound)

	let local: [String: LocalEntry]
	let remote: [String: RemoteEntry]

	/// Upper-cased local command names, with and without the developer-mode
	/// ones. Both are settled here, which is what the cache the old storage
	/// kept -- and had to invalidate -- was standing in for.
	private let publicCommandNames: [String]
	private let allCommandNames: [String]

	var isEmpty: Bool {
		local.isEmpty && remote.isEmpty
	}

	init(local: [String: LocalEntry], remote: [String: RemoteEntry]) {
		self.local = local
		self.remote = remote
		allCommandNames = local.keys.map { $0.uppercased() }
		publicCommandNames = local
			.filter { $0.value.isDeveloperModeOnly == false }
			.keys
			.map { $0.uppercased() }
	}

	func commandNames(developerModeEnabled: Bool) -> [String] {
		developerModeEnabled ? allCommandNames : publicCommandNames
	}

	static func loaded() -> CommandIndexTables {
		let localValues = ResourceManager.dictionary(
			fromResources: "IRCCommandIndexLocalData",
			cacheValue: false
		)
		let remoteValues = ResourceManager.dictionary(
			fromResources: "IRCCommandIndexRemoteData",
			cacheValue: false
		)

		assert(localValues != nil)
		assert(remoteValues != nil)

		return CommandIndexTables(
			local: commandData(from: localValues).mapValues { data in
				LocalEntry(
					index: unsignedIntegerValue(data[Key.indexValue]),
					isDeveloperModeOnly: data[Key.developerModeOnly]?.boolean ?? false,
					arguments: data[Key.arguments]?.string
				)
			},
			remote: commandData(from: remoteValues).mapValues { data in
				RemoteEntry(
					index: unsignedIntegerValue(data[Key.indexValue]),
					outgoingColonIndex: data[Key.outgoingColonIndex]?.integer ?? 0
				)
			}
		)
	}

	private static let reservedKey = "Reserved Information"

	private static func commandData(
		from values: [String: PropertyListValue]?
	) -> [String: [String: PropertyListValue]] {
		guard var values else {
			return [:]
		}

		values.removeValue(forKey: reservedKey)

		return values.compactMapValues(\.dictionary)
	}

	private static func unsignedIntegerValue(_ value: PropertyListValue?) -> UInt {
		value?.integer.map(UInt.init(clamping:)) ?? 0
	}

	private enum Key {
		static let arguments = "arguments"
		static let developerModeOnly = "developerModeOnly"
		static let indexValue = "indexValue"
		static let outgoingColonIndex = "outgoingColonIndex"
	}
}
