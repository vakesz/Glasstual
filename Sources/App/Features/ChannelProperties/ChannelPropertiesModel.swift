// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Observation
import SwiftUI

enum ChannelPropertiesSection: Int, CaseIterable, Identifiable {
	case general
	case defaults

	var id: Int {
		rawValue
	}

	var title: LocalizedStringResource {
		switch self {
		case .general: .ChannelProperties.general
		case .defaults: .ChannelProperties.defaults
		}
	}
}

@MainActor
@Observable
final class ChannelPropertiesModel {
	var isSaving = false
	var config: ConversationConfig
	var selection: ChannelPropertiesSection = .general
	let channelNameIsEditable: Bool

	/// Whether the name in the field is one the server would accept.
	var channelNameIsValid: Bool {
		isChannelName(config.name.firstToken)
	}

	/// Why the name cannot be saved, once saving has been tried.
	var channelNameValidationMessage: String? {
		submission.shown(channelNameIsValid
			? nil
			: String(localized: .ChannelProperties.pleaseEnterAProperlyFormattedChannel))
	}

	private var submission = SubmissionGate()

	/** The connection whose ISUPPORT decides what a channel name looks like.

	 Weak because the sheet outlives nothing and the session outlives the sheet;
	 a session that goes away mid-edit simply leaves the syntactic check behind,
	 which is what a sheet opened without one uses anyway. */
	private weak var session: ServerSession?

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

	init(config: ConversationConfig, session: ServerSession? = nil) {
		self.config = config
		self.session = session
		channelNameIsEditable = config.name.isEmpty
		secretKeyText = config.pendingSecretKey.value(orStored: nil) ?? ""
	}

	/** Whether this conversation is silenced.

	 The setting is stored the other way round, as whether notifications are
	 shown, and the key that holds it is what earlier releases wrote. The
	 switch reads as Messages' does, so the model is what inverts it rather
	 than every reader of the configuration. */
	var isMuted: Bool {
		get { config.pushNotifications == false }
		set { config.pushNotifications = newValue == false }
	}

	/** The channel's inline-media override, which is one switch and not two.

	 `inlineMediaDisabled` and `inlineMediaEnabled` are the two halves of one
	 override, and
	 `TranscriptController.inlineMediaEnabledForView` consults exactly one of them
	 depending on the application-wide setting. Editing both leaves whichever
	 does not match the setting inert, and lets the channel end up asking for
	 media to be hidden and shown at the same time. */
	var overridesInlineMediaByDisabling: Bool {
		SettingsKeys.Messages.showInlineMedia.value
	}

	var inlineMediaOverrideTitle: LocalizedStringResource {
		overridesInlineMediaByDisabling
			? .ChannelProperties.disableInlineMedia
			: .ChannelProperties.showInlineMedia
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
		submission.attempt()
		guard channelNameIsValid else {
			selection = .general
			return false
		}
		return true
	}

	var submittedConfig: ConversationConfig {
		var result = config
		result.name = config.name.firstToken
		result.label = Self.trimmedOrNil(config.label)
		result.defaultModes = Self.trimmedOrNil(config.defaultModes)
		result.defaultTopic = Self.trimmedOrNil(config.defaultTopic)
		result.pendingSecretKey = secretKeyWasEdited
			? .edited(secretKey.firstToken)
			: config.pendingSecretKey
		return result
	}

	func replace(with config: ConversationConfig) {
		self.config = config
		submission.reset()
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

	/** The server's limit on a channel key against what is used of it. `nil`
	 when no connection has advertised one, because a limit nobody named would
	 be a guess. */
	private var secretKeyLimit: ServerLengthLimit? {
		guard let session else { return nil }

		return ServerLengthLimit(using: secretKey.firstToken, maximum: session.supportInfo.maximumKeyLength)
	}

	/** What to say under the password field about the server's key length.

	 A modal alert used to interrupt the person mid-keystroke — once per sheet,
	 suppressible, and gone the moment it was dismissed. The counter is there
	 the whole time the field is, and becomes the warning as soon as the key is
	 longer than the server accepts. */
	var secretKeyLengthCaption: String? {
		guard let session, let limit = secretKeyLimit else { return nil }
		guard limit.isExceeded else {
			return String(localized: .ChannelProperties.secretKeyLength(limit.used, limit.maximum))
		}

		return String(localized: .ChannelProperties.secretKeyTooLong(session.networkNameAlt, limit.maximum))
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
	 there is a session to ask, its ISUPPORT is the answer. */
	private func isChannelName(_ candidate: String) -> Bool {
		guard candidate.isEmpty == false else {
			return false
		}

		guard let session else {
			return candidate.isChannelName
		}

		return candidate.isChannelName(on: session)
	}

	/// What an edited optional field is worth once it is saved: its text without
	/// the whitespace around it, or nothing at all when that leaves it empty.
	private static func trimmedOrNil(_ value: String?) -> String? {
		let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return trimmed.isEmpty ? nil : trimmed
	}
}
