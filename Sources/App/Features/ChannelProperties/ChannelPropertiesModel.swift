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
	/** The connection whose ISUPPORT decides what a channel name looks like.

	 Weak because the sheet outlives nothing and the client outlives the sheet;
	 a client that goes away mid-edit simply leaves the syntactic check behind,
	 which is what a sheet opened without one uses anyway. */
	private weak var client: IRCClient?

	init(config: ChannelConfig, client: IRCClient? = nil) {
		self.config = config
		self.client = client
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
		channelNameValidationError = isChannelName(candidate)
			? nil
			: ChannelPropertiesStrings.invalidChannelName
	}

	/** Whether the server this channel belongs to would call `candidate` a
	 channel name.

	 The connection-less check is a union of the prefixes networks are known to
	 use, which is both too wide and too narrow: it accepts a `~channel` on a
	 server that has no such type, and refuses a name under any `CHANTYPES` the
	 list does not happen to include, so the name could never be saved. When
	 there is a client to ask, its ISUPPORT is the answer. */
	private func isChannelName(_ candidate: String) -> Bool {
		guard candidate.isEmpty == false else {
			return false
		}

		guard let client else {
			return (candidate as NSString).isChannelName
		}

		return (candidate as NSString).isChannelName(on: client)
	}

	private static func nilIfEmpty(_ value: String) -> String? {
		value.isEmpty ? nil : value
	}
}
