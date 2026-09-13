/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
import Observation

@MainActor
@Observable
final class HighlightEntryModel {
	let channels: [HighlightEntryChannel]

	private var workingConfiguration: HighlightMatchCondition

	var behavior: HighlightMatchBehavior
	var keyword: String

	/// A channel the connection no longer has is not a channel to limit a rule
	/// to, so choosing one falls back to every channel.
	var channelSelection: HighlightChannelSelection {
		didSet {
			if case let .channel(id) = channelSelection,
			   channels.contains(where: { $0.id == id }) == false
			{
				channelSelection = .all
			}
		}
	}

	var validationError: String? {
		Self.validationError(for: keyword)
	}

	/// The refusal, once saving has been tried. A new rule opens on an empty
	/// keyword, and saying so before anything was typed is not a refusal.
	var validationMessage: String? {
		submissionWasAttempted ? validationError : nil
	}

	private var submissionWasAttempted = false

	init(
		configuration: HighlightMatchCondition?,
		channels: [HighlightEntryChannel]
	) {
		let workingConfiguration = configuration ?? HighlightMatchCondition()
		let availableChannelIDs = Set(channels.map(\.id))

		self.channels = channels
		self.workingConfiguration = workingConfiguration
		behavior = HighlightMatchBehavior(excludesMatches: workingConfiguration.matchIsExcluded)
		keyword = workingConfiguration.matchKeyword

		if let channelID = workingConfiguration.matchChannelId,
		   availableChannelIDs.contains(channelID)
		{
			channelSelection = .channel(id: channelID)
		} else {
			channelSelection = .all
		}
	}

	var normalizedKeyword: String {
		keyword.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	@discardableResult
	func validateForSubmission() -> Bool {
		submissionWasAttempted = true

		return validationError == nil
	}

	func configurationForSubmission() -> HighlightMatchCondition {
		workingConfiguration.matchIsExcluded = behavior.excludesMatches
		workingConfiguration.matchKeyword = normalizedKeyword
		workingConfiguration.matchChannelId = channelSelection.channelID

		return workingConfiguration
	}

	private static func validationError(for keyword: String) -> String? {
		let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)

		guard trimmed.isEmpty == false else {
			return ApplicationStrings.requiredField
		}

		return HighlightKeywordPattern.validationError(
			for: trimmed,
			usesRegularExpression: HighlightKeywordPattern.matchesByRegularExpression
		)
	}
}

/** Whether a highlight keyword is one the matcher can actually use.

 The Highlights pane decides how every keyword is matched, so a keyword saved
 while that is Regular Expression has to compile. Nothing used to check: the
 renderer builds the expression with `try?` and an unusable pattern simply
 stopped highlighting, with nothing said anywhere. */
nonisolated enum HighlightKeywordPattern { // nonisolated: value
	@MainActor
	static var matchesByRegularExpression: Bool {
		Preferences.Highlights.matchingMethod.value == .regularExpression
	}

	static func validationError(for keyword: String, usesRegularExpression: Bool) -> String? {
		guard usesRegularExpression, isValid(keyword) == false else {
			return nil
		}

		return ApplicationStrings.invalidRegularExpression
	}

	static func isValid(_ pattern: String) -> Bool {
		(try? NSRegularExpression(pattern: pattern)) != nil
	}
}
