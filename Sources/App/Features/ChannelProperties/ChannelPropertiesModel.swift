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

	/** The channel's inline-media override, which is one switch and not two.

	 `inlineMediaDisabled` and `inlineMediaEnabled` are the two halves of a
	 single override migrated from one boolean, and
	 `LogController.inlineMediaEnabledForView` consults exactly one of them
	 depending on the application-wide preference. Editing both leaves whichever
	 does not match the preference inert, and lets the channel end up asking for
	 media to be hidden and shown at the same time. */
	var overridesInlineMediaByDisabling: Bool {
		Preferences.Messages.showInlineMedia.value
	}

	var inlineMediaOverrideTitle: String {
		overridesInlineMediaByDisabling
			? ChannelPropertiesStrings.disableInlineMedia
			: ChannelPropertiesStrings.showInlineMedia
	}

	var inlineMediaOverride: Bool {
		get { overridesInlineMediaByDisabling ? config.inlineMediaDisabled : config.inlineMediaEnabled }
		set {
			if overridesInlineMediaByDisabling {
				config.inlineMediaDisabled = newValue
			} else {
				config.inlineMediaEnabled = newValue
			}
		}
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
