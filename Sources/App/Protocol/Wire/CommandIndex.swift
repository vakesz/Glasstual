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

/// The names `/`-completion offers.
///
/// Everything else a command declares is a property of `LocalCommand` or
/// `RemoteCommand`; only the completion lists are worth keeping built.
enum CommandIndex {
	static func localCommandList() -> [String] {
		Preferences.Commands.developerMode.value ? allCommandNames : publicCommandNames
	}

	private static let allCommandNames = LocalCommand.allCases.map(\.displayName)

	private static let publicCommandNames = LocalCommand.allCases
		.filter { $0.isDeveloperModeOnly == false }
		.map(\.displayName)
}

/// How many argument groups a command's documented syntax declares.
///
/// Every top-level `<group>` is required and every `[group]` is optional. It
/// describes the documented syntax, not what a particular handler goes on to
/// read.
nonisolated struct CommandArity: Sendable, Equatable { // nonisolated: value
	let required: Int
	let optional: Int

	static let none = CommandArity(required: 0, optional: 0)

	init(required: Int, optional: Int) {
		self.required = required
		self.optional = optional
	}

	init(syntax: String?) {
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
