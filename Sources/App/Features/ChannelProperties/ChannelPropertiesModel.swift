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
	let channelNameIsEditable: Bool

	/// Whether the name in the field is one the server would accept.
	var channelNameIsValid: Bool {
		isChannelName(channelName.firstToken)
	}

	/** Why the name cannot be saved, once saving has been tried.

	 A sheet for a channel that does not exist yet opens on an empty field, and
	 the message used to be there — with a red border around the field — before
	 anything had been typed into it. */
	var channelNameValidationMessage: String? {
		submissionWasAttempted && channelNameIsValid == false
			? ChannelPropertiesStrings.invalidChannelName
			: nil
	}

	private var submissionWasAttempted = false

	/** The connection whose ISUPPORT decides what a channel name looks like.

	 Weak because the sheet outlives nothing and the client outlives the sheet;
	 a client that goes away mid-edit simply leaves the syntactic check behind,
	 which is what a sheet opened without one uses anyway. */
	private weak var client: IRCClient?

	init(config: ChannelConfig, client: IRCClient? = nil) {
		self.config = config
		self.client = client
		channelNameIsEditable = config.channelName.isEmpty
	}

	var channelName: String {
		get { config.channelName }
		set { config.channelName = newValue }
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
		submissionWasAttempted = true
		guard channelNameIsValid else {
			selection = .general
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
		submissionWasAttempted = false
	}

	/// What a connection says about how long a channel key may be, and how much
	/// of that the field holds.
	private struct SecretKeyLimit {
		let used: Int
		let maximum: Int
		let networkName: String

		var isExceeded: Bool {
			used > maximum
		}
	}

	/** The server's limit on a channel key, what is used of it, and who said
	 so. `nil` when no connection has advertised one, because a limit nobody
	 named would be a guess. */
	private var secretKeyLimit: SecretKeyLimit? {
		guard let client else { return nil }
		let maximum = Int(clamping: client.supportInfo.maximumKeyLength)
		guard maximum > 0 else { return nil }

		return SecretKeyLimit(used: secretKey.count, maximum: maximum, networkName: client.networkNameAlt)
	}

	/** What to say under the password field about the server's key length.

	 A modal alert used to interrupt the person mid-keystroke — once per sheet,
	 suppressible, and gone the moment it was dismissed. The counter is there
	 the whole time the field is, and becomes the warning as soon as the key is
	 longer than the server accepts. */
	var secretKeyLengthCaption: String? {
		guard let limit = secretKeyLimit else { return nil }
		guard limit.isExceeded else {
			return ChannelPropertiesStrings.secretKeyLength(limit.used, maximum: limit.maximum)
		}

		return ChannelPropertiesStrings.secretKeyTooLong(
			networkName: limit.networkName,
			maximumLength: limit.maximum
		)
	}

	var secretKeyIsTooLong: Bool {
		secretKeyLimit?.isExceeded ?? false
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
