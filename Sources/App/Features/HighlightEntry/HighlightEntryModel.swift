/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

	private let workingConfiguration: MutableHighlightMatchCondition

	private(set) var behavior: HighlightMatchBehavior
	private(set) var keyword: String
	private(set) var channelSelection: HighlightChannelSelection
	private(set) var validationError: String?
	var isValidationMessagePresented = false

	init(
		configuration: HighlightMatchCondition?,
		channels: [HighlightEntryChannel]
	) {
		let workingConfiguration = Self.mutableConfiguration(copying: configuration)
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

		validationError = Self.validationError(for: workingConfiguration.matchKeyword)
	}

	var normalizedKeyword: String {
		keyword.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	func setBehavior(_ behavior: HighlightMatchBehavior) {
		self.behavior = behavior
	}

	func updateKeyword(_ keyword: String) {
		self.keyword = keyword
		refreshValidation()
		isValidationMessagePresented = false
	}

	func setChannelSelection(_ selection: HighlightChannelSelection) {
		switch selection {
		case .all:
			channelSelection = .all
		case let .channel(id):
			channelSelection = channels.contains(where: { $0.id == id }) ? selection : .all
		}
	}

	@discardableResult
	func validateForSubmission() -> Bool {
		refreshValidation()
		isValidationMessagePresented = validationError != nil
		return validationError == nil
	}

	func configurationForSubmission() -> HighlightMatchCondition {
		workingConfiguration.matchIsExcluded = behavior.excludesMatches
		workingConfiguration.matchKeyword = normalizedKeyword
		workingConfiguration.matchChannelId = channelSelection.channelID

		guard let configuration = workingConfiguration.copy() as? HighlightMatchCondition else {
			preconditionFailure("Highlight configuration copies must preserve their model type")
		}

		return configuration
	}

	private func refreshValidation() {
		validationError = Self.validationError(for: keyword)
	}

	private static func validationError(for keyword: String) -> String? {
		keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			? ApplicationStrings.requiredField
			: nil
	}

	private static func mutableConfiguration(
		copying configuration: HighlightMatchCondition?
	) -> MutableHighlightMatchCondition {
		guard let configuration else {
			return MutableHighlightMatchCondition()
		}

		guard let copy = configuration.mutableCopy() as? MutableHighlightMatchCondition else {
			preconditionFailure("Highlight configuration mutable copies must preserve their model type")
		}

		return copy
	}
}
