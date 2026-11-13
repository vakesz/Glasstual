// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What a card says to type to answer it.

 The exact command, so nobody has to copy one out of the conversation: a
 security question shows the spelled-out answer, since `/yes` does not answer
 it, and a question an asker's own command answers shows that command too. */
nonisolated enum PromptHint {
	/// The commands, separated for reading. Command tokens are not localized.
	static func commands(for request: AlertRequest, number: Int) -> [String] {
		if request.isNotice {
			return ["/yes"]
		}
		if request.field != nil {
			return ["/answer \(number)", "/no"]
		}
		if let reference = request.reference, let dcc = dccCommands(for: request, reference: reference) {
			return dcc
		}
		if request.affirmativeButton != nil, request.responses.count == 2 {
			return ["/yes", "/no"]
		}
		let choices = request.responses
			.filter { $0 != request.escapeButton }
			.map { request.keyword(for: $0).rawValue }
		return choices.map { "/answer \(number) \($0)" } + ["/no"]
	}

	/// The `/dcc` form of a DCC question, which answers it as well as `/answer`.
	private static func dccCommands(for request: AlertRequest, reference: String) -> [String]? {
		let keywords = request.responses.map { request.keyword(for: $0) }
		if keywords.contains(.accept) {
			return ["/dcc accept \(reference)", "/dcc decline \(reference)"]
		}
		let trust: Set<PromptKeyword> = [.remember, .once, .replace, .reject]
		guard keywords.allSatisfy({ trust.contains($0) }) else { return nil }
		let words = keywords.filter { $0 != .reject }.map(\.rawValue) + [PromptKeyword.reject.rawValue]
		return ["/dcc trust \(reference) " + words.joined(separator: "|")]
	}
}
