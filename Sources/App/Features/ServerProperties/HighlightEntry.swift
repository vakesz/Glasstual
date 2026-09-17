// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation
import SwiftUI

enum HighlightMatchBehavior: CaseIterable, Hashable, Identifiable, Sendable {
	case include
	case exclude

	init(excludesMatches: Bool) {
		self = excludesMatches ? .exclude : .include
	}

	var id: Self {
		self
	}

	var excludesMatches: Bool {
		self == .exclude
	}

	/// How the picker names the two halves of the rule.
	var title: LocalizedStringResource {
		switch self {
		case .include: .ServerProperties.serverSpecificHighlightEntryMatch
		case .exclude: .ServerProperties.serverSpecificHighlightEntryExclude
		}
	}
}

struct HighlightEntryChannel: Equatable, Hashable, Identifiable, Sendable {
	let id: String
	let name: String
}

enum HighlightChannelSelection: Equatable, Hashable, Sendable {
	case all
	case channel(id: String)

	var channelID: String? {
		switch self {
		case .all:
			nil
		case let .channel(id):
			id
		}
	}
}

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
nonisolated enum HighlightKeywordPattern {
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

@MainActor
final class HighlightEntrySheet: SheetSession {
	let model: HighlightEntryModel

	/// The rule the person accepted.
	private let onSave: (HighlightMatchCondition) -> Void

	init(
		config: HighlightMatchCondition?,
		channels: [ChannelConfig],
		onSave: @escaping (HighlightMatchCondition) -> Void
	) {
		self.onSave = onSave
		model = HighlightEntryModel(
			configuration: config,
			channels: channels.map {
				HighlightEntryChannel(id: $0.uniqueIdentifier, name: $0.channelName)
			}
		)

		super.init(window: nil)
		installSheet()
	}

	private func installSheet() {
		let rootView = HighlightEntryView(
			model: model,
			submit: { [weak self] in
				self?.submit()
			},
			cancel: { [weak self] in
				self?.cancel()
			}
		)
		setContent(rootView)
	}

	func start() {
		startSheet()
	}

	override func submit() {
		guard model.validateForSubmission() else {
			return
		}

		onSave(model.configurationForSubmission())

		super.submit()
	}
}
