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

	/** The key field's text.

	 It starts from the unflushed edit alone, holds whatever the one keychain
	 read finds, and is only submitted as an edit once the person typed into it.
	 The read lands after the sheet is on screen, so an untouched field that
	 submitted its empty text would delete the key the sheet had not finished
	 showing. */
	var secretKey: String {
		get { secretKeyText }
		set {
			guard newValue != secretKeyText else { return }
			secretKeyText = newValue
			secretKeyWasEdited = true
		}
	}

	private var secretKeyText: String
	private var secretKeyWasEdited = false

	/// Changes whenever the stored key has to be read again, which the view
	/// keys its loading task on.
	private(set) var secretKeyLoadGeneration = 0

	/** The Notifications pane's table.

	 Its rows copy the channel's overrides when they are made, so the model is
	 built again whenever the configuration is replaced. */
	private(set) var notificationConfiguration = NotificationConfigurationModel(
		notifications: [],
		allowsInheritedState: true
	)

	/// The events a channel can override, in the order the pane lists them,
	/// with a separator between each group.
	private static let notificationEvents: [NotificationEvent?] = [
		.highlight, nil, .channelMessage, .channelNotice, nil, .userJoined, .userParted,
	]

	init(config: ChannelConfig, client: IRCClient? = nil) {
		self.config = config
		self.client = client
		channelNameIsEditable = config.channelName.isEmpty
		secretKeyText = config.pendingSecretKey.value(orStored: nil) ?? ""
		rebuildNotificationConfiguration()
	}

	private func rebuildNotificationConfiguration() {
		notificationConfiguration = NotificationConfigurationModel(
			notifications: Self.notificationEvents.map { event in
				event.map { .configuration(ChannelNotificationConfiguration(eventType: $0, in: self)) } ?? .separator
			},
			allowsInheritedState: true
		)
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
		result.pendingSecretKey = secretKeyWasEdited
			? .edited(secretKey.firstToken)
			: config.pendingSecretKey
		return result
	}

	func replace(with config: ChannelConfig) {
		self.config = config
		submissionWasAttempted = false
		rebuildNotificationConfiguration()
		/* The replacement is what the channel now stores, and saving it may have
		 rewritten the keychain item, so the field starts over and reads it
		 again rather than trusting the last read. */
		secretKeyWasEdited = false
		secretKeyText = config.pendingSecretKey.value(orStored: nil) ?? ""
		secretKeyLoadGeneration += 1
	}

	/** Reads the stored channel key off the main actor and shows it, unless
	 the field has been typed into — an emptied field included — or the
	 configuration already carries an edit of its own.

	 `SecItemCopyMatching` is synchronous: the field's binding and the length
	 caption used to call it from the view body, several times per redraw. */
	func loadSecretKey() async {
		guard case .unchanged = config.pendingSecretKey else { return }

		let item = config.keychainItem
		let stored = await KeychainSecretLoader.passwords(for: [item])[item]

		guard Task.isCancelled == false,
		      item == config.keychainItem,
		      secretKeyWasEdited == false,
		      case .unchanged = config.pendingSecretKey
		else {
			return
		}

		secretKeyText = stored ?? ""
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
