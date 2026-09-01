/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Observation

enum ChannelPropertiesSection: Int, CaseIterable, Identifiable {
	case general
	case defaults
	case notifications

	var id: Int {
		rawValue
	}

	var title: String {
		switch self {
		case .general: ChannelPropertiesStrings.general
		case .defaults: ChannelPropertiesStrings.defaults
		case .notifications: ChannelPropertiesStrings.notifications
		}
	}
}

@MainActor
@Observable
final class ChannelPropertiesModel {
	var config: ChannelConfig
	var selection: ChannelPropertiesSection = .general
	private(set) var channelNameValidationError: String?
	var isValidationMessagePresented = false
	let channelNameIsEditable: Bool

	init(config: ChannelConfig) {
		self.config = config
		channelNameIsEditable = config.channelName.isEmpty
		refreshValidation()
	}

	var channelName: String {
		get { config.channelName }
		set {
			config.channelName = newValue
			refreshValidation()
			isValidationMessagePresented = false
		}
	}

	var label: String {
		get { config.label ?? "" }
		set { config.label = newValue }
	}

	var defaultModes: String {
		get { config.defaultModes ?? "" }
		set { config.defaultModes = newValue }
	}

	var defaultTopic: String {
		get { config.defaultTopic ?? "" }
		set { config.defaultTopic = newValue }
	}

	var secretKey: String {
		get { config.secretKey ?? "" }
		set { config.secretKey = newValue }
	}

	@discardableResult
	func validateForSubmission() -> Bool {
		refreshValidation()
		if channelNameValidationError != nil {
			selection = .general
			isValidationMessagePresented = true
			return false
		}
		return true
	}

	var submittedConfig: ChannelConfig {
		var result = config
		result.channelName = channelName.firstToken
		result.label = Self.nilIfEmpty(label.trimmingCharacters(in: .whitespacesAndNewlines))
		result.defaultModes = Self.nilIfEmpty(defaultModes.trimmingCharacters(in: .whitespacesAndNewlines))
		result.defaultTopic = Self.nilIfEmpty(defaultTopic.trimmingCharacters(in: .whitespacesAndNewlines))
		result.secretKey = Self.nilIfEmpty(secretKey.firstToken)
		return result
	}

	func replace(with config: ChannelConfig) {
		self.config = config
		refreshValidation()
		isValidationMessagePresented = false
	}

	private func refreshValidation() {
		let candidate = channelName.firstToken
		channelNameValidationError = candidate.isEmpty || (candidate as NSString).isChannelName == false
			? ChannelPropertiesStrings.invalidChannelName
			: nil
	}

	private static func nilIfEmpty(_ value: String) -> String? {
		value.isEmpty ? nil : value
	}
}
