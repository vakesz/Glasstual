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

import Foundation

@objc(IRCCommandIndex)
public final class CommandIndex: NSObject {
	private static let storage = CommandIndexStorage()

	@objc(populateCommandIndex)
	public static func populateCommandIndex() {
		storage.populateIfNeeded()
	}

	@objc(invalidateCaches)
	public static func invalidateCaches() {
		storage.invalidateCaches()
	}

	@objc(localCommandList)
	public static func localCommandList() -> [String] {
		storage.localCommandList(developerModeEnabled: TextualPreferences.developerModeEnabled())
	}

	@objc(indexOfRemoteCommand:)
	public static func index(ofRemoteCommand command: String) -> UInt {
		storage.index(of: command, isLocal: false, developerModeEnabled: false)
	}

	@objc(indexOfLocalCommand:)
	public static func index(ofLocalCommand command: String) -> UInt {
		storage.index(
			of: command,
			isLocal: true,
			developerModeEnabled: TextualPreferences.developerModeEnabled()
		)
	}

	@objc(colonPositionForRemoteCommand:)
	public static func colonPosition(forRemoteCommand command: String) -> UInt {
		storage.colonPosition(forRemoteCommand: command)
	}

	@objc(syntaxForLocalCommand:)
	public static func syntax(forLocalCommand command: String) -> String? {
		storage.syntax(forLocalCommand: command)
	}

	/// Everything the index knows about one local command, or `nil` when the
	/// name is not in the index. Unlike `index(ofLocalCommand:)` this does not
	/// hide developer-mode commands: it reports the flag, so the dispatcher can
	/// refuse such a command with a message instead of mistaking it for one it
	/// has never heard of and forwarding it to the server.
	public static func descriptor(forLocalCommand command: String) -> LocalCommandDescriptor? {
		storage.descriptor(forLocalCommand: command)
	}
}

/// How many argument groups a command's index entry declares.
///
/// Counted from the syntax string the index carries: every top-level `<group>`
/// is required and every `[group]` is optional. It describes the documented
/// syntax, not what a particular handler goes on to read.
public nonisolated struct CommandArity: Sendable, Equatable {
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
public nonisolated struct LocalCommandDescriptor: Sendable {
	public let command: IRCLocalCommand

	/// The command is kept out of completion and refused unless the
	/// developer-mode preference is on.
	public let isDeveloperModeOnly: Bool

	public let arity: CommandArity
}

/* ISOLATION-EXCEPTION: the command tables are built once and read from the
 command dispatcher and the plugin queue alike; the storage is lock-guarded. */
private final class CommandIndexStorage: @unchecked Sendable {
	private typealias CommandData = [String: [String: Any]]

	private static let reservedKey = "Reserved Information"
	private static let notFound = UInt(NSNotFound)

	private let lock = NSLock()
	private var hasPopulated = false
	private var localData: CommandData = [:]
	private var remoteData: CommandData = [:]
	private var cachedLocalCommandList: [String]?

	func populateIfNeeded() {
		withLock {
			guard hasPopulated == false else {
				return
			}

			hasPopulated = true

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

			localData = commandData(from: localValues)
			remoteData = commandData(from: remoteValues)
		}
	}

	func invalidateCaches() {
		withLock {
			cachedLocalCommandList = nil
		}
	}

	func localCommandList(developerModeEnabled: Bool) -> [String] {
		withLock {
			if let cachedLocalCommandList {
				return cachedLocalCommandList
			}

			var commandList: [String] = []

			for (command, data) in localData {
				if developerModeEnabled == false, boolValue(data[Key.developerModeOnly]) {
					continue
				}

				commandList.append(command.uppercased())
			}

			cachedLocalCommandList = commandList

			return commandList
		}
	}

	func index(of command: String, isLocal: Bool, developerModeEnabled: Bool) -> UInt {
		withLock {
			let data = isLocal ? localData[command.lowercased()] : remoteData[command.lowercased()]

			guard let data else {
				return Self.notFound
			}

			if isLocal,
			   developerModeEnabled == false,
			   boolValue(data[Key.developerModeOnly])
			{
				return Self.notFound
			}

			return unsignedIntegerValue(data[Key.indexValue])
		}
	}

	func descriptor(forLocalCommand command: String) -> LocalCommandDescriptor? {
		withLock {
			guard let data = localData[command.lowercased()],
			      let value = IRCLocalCommand(rawValue: unsignedIntegerValue(data[Key.indexValue]))
			else {
				return nil
			}

			return LocalCommandDescriptor(
				command: value,
				isDeveloperModeOnly: boolValue(data[Key.developerModeOnly]),
				arity: CommandArity(syntax: data[Key.arguments] as? String)
			)
		}
	}

	func colonPosition(forRemoteCommand command: String) -> UInt {
		withLock {
			guard let data = remoteData[command.lowercased()] else {
				return Self.notFound
			}

			let position = integerValue(data[Key.outgoingColonIndex])

			return position < 0 ? Self.notFound : UInt(position)
		}
	}

	func syntax(forLocalCommand command: String) -> String? {
		withLock {
			guard let data = localData[command.lowercased()] else {
				return nil
			}

			let command = command.uppercased()

			guard let arguments = data[Key.arguments] as? String else {
				return command
			}

			return "\(command) \(arguments)"
		}
	}

	private func commandData(from values: [String: Any]?) -> CommandData {
		guard var values else {
			return [:]
		}

		values.removeValue(forKey: Self.reservedKey)

		return values.compactMapValues { $0 as? [String: Any] }
	}

	private func boolValue(_ value: Any?) -> Bool {
		(value as? NSNumber)?.boolValue ?? false
	}

	private func integerValue(_ value: Any?) -> Int {
		(value as? NSNumber)?.intValue ?? 0
	}

	private func unsignedIntegerValue(_ value: Any?) -> UInt {
		(value as? NSNumber)?.uintValue ?? 0
	}

	private func withLock<Result>(_ body: () -> Result) -> Result {
		lock.lock()
		defer { lock.unlock() }

		return body()
	}

	private enum Key {
		static let arguments = "arguments"
		static let developerModeOnly = "developerModeOnly"
		static let indexValue = "indexValue"
		static let outgoingColonIndex = "outgoingColonIndex"
	}
}
