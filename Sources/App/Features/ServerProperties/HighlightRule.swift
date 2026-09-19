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

struct HighlightRuleChannel: Equatable, Hashable, Identifiable, Sendable {
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
final class HighlightRuleModel {
	let channels: [HighlightRuleChannel]

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

	/// The refusal, once saving has been tried.
	var validationMessage: String? {
		submission.shown(validationError)
	}

	private var submission = SubmissionGate()

	init(
		configuration: HighlightMatchCondition?,
		channels: [HighlightRuleChannel]
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
		submission.attempt()

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

@MainActor
final class HighlightRuleSheet: SheetSession {
	let model: HighlightRuleModel

	/// The rule the person accepted.
	private let onSave: (HighlightMatchCondition) -> Void

	init(
		config: HighlightMatchCondition?,
		channels: [ConversationConfig],
		onSave: @escaping (HighlightMatchCondition) -> Void
	) {
		self.onSave = onSave
		model = HighlightRuleModel(
			configuration: config,
			channels: channels.map {
				HighlightRuleChannel(id: $0.uniqueIdentifier, name: $0.name)
			}
		)

		super.init(window: nil)
		installSheet()
	}

	private func installSheet() {
		let rootView = HighlightRuleView(
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

	override func submit() {
		guard model.validateForSubmission() else {
			return
		}

		onSave(model.configurationForSubmission())

		super.submit()
	}
}

// MARK: - Sheet content

@MainActor
private struct HighlightRuleView: View {
	@Bindable var model: HighlightRuleModel

	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var keywordFieldIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			SheetHeading(.ServerProperties.highlightRuleWindowTitle, subtitle: Text(.ServerProperties.ruleDescription))

			Form {
				Section {
					Picker(.ServerProperties.matchTypeLabel, selection: $model.behavior) {
						ForEach(HighlightMatchBehavior.allCases) { behavior in
							Text(behavior.title).tag(behavior)
						}
					}

					LabeledContent(.ServerProperties.keywordLabel) {
						TextField(.ServerProperties.keywordPlaceholder, text: $model.keyword)
							.labelsHidden()
							.focused($keywordFieldIsFocused)
							.accessibilityLabel(.ServerProperties.keywordLabel)
							.onSubmit(submit)
					}

					if let message = model.validationMessage {
						ValidationMessageLabel(message)
					}
				} footer: {
					Text(.ServerProperties.keywordHelp)
				}

				Section {
					Picker(.ServerProperties.channelLabel, selection: $model.channelSelection) {
						Text(.ServerProperties.allChannels)
							.tag(HighlightChannelSelection.all)

						if model.channels.isEmpty == false {
							Divider()
						}

						ForEach(model.channels) { channel in
							Text(verbatim: channel.name)
								.tag(HighlightChannelSelection.channel(id: channel.id))
						}
					}
				} footer: {
					Text(.ServerProperties.channelHelp)
				}
			}
			.formStyle(.grouped)

			/* The rule is written back into the connection the sheet belongs to,
			 which is what saves it. */
			SheetActions(
				confirmTitle: .sheetConfirmation,
				confirmIsDisabled: model.validationMessage != nil,
				confirm: submit,
				cancel: cancel
			)
		}
		.frame(minWidth: 460, idealWidth: 520, maxWidth: .infinity)
		.onAppear {
			keywordFieldIsFocused = true
		}
	}
}
