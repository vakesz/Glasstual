/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation

/** Owns the user's message rules: the stored list, the store the Rules pane
 edits, and the engine the inbound path asks.

 The rules live in one preference, so a configuration import is a write to it
 like any other. The change notification is what brings an import back in,
 which is why the list is re-read rather than kept only in memory. */
@MainActor
final class MessageRuleController {
	private(set) lazy var store = MessageRuleStore { [weak self] rules in
		self?.save(rules)
	}

	private lazy var engine = MessageRuleEngine { [weak self] in
		self?.store.rules ?? []
	}

	private var savedConfigurations: [PropertyListValue]?
	private let notifications = NotificationSubscriptions()

	init() {
		notifications.observe(.glasstualUserDefaultsDidChange) { [weak self] notification in
			let changedKey = notification.userInfo?[
				PreferenceChangeNotification.changedKeyUserInfoKey
			] as? String
			guard changedKey == nil || changedKey == Preferences.Rules.messageRules.name else { return }
			self?.load()
		}
		load()
	}

	/// Whether a received chat line may be printed.
	func shouldPrintText(
		_ text: String,
		authoredBy author: Prefix,
		destinedFor destination: Channel?,
		as lineType: LogLineType,
		onClient client: Client,
		receivedAt: Date,
		wasEncrypted: Bool
	) -> Bool {
		engine.shouldPrintText(
			text,
			authoredBy: author,
			destinedFor: destination,
			as: lineType,
			onClient: client,
			receivedAt: receivedAt,
			wasEncrypted: wasEncrypted
		)
	}

	/// Whether a received command may be printed.
	func shouldPrintCommand(
		_ command: String,
		text: String?,
		authoredBy author: Prefix,
		destinedFor destination: Channel?,
		onClient client: Client,
		receivedAt: Date,
		messageParameters: [String]
	) -> Bool {
		engine.shouldPrintCommand(
			command,
			text: text,
			authoredBy: author,
			destinedFor: destination,
			onClient: client,
			receivedAt: receivedAt,
			messageParameters: messageParameters
		)
	}

	private func load() {
		let configurations = Preferences.Rules.messageRules.propertyListValue?.array ?? []
		guard configurations != savedConfigurations else { return }
		savedConfigurations = configurations
		store.replaceAll(with: configurations.compactMap(\.dictionary).map(MessageRule.init(dictionary:)))
		engine.rulesDidChange()
	}

	private func save(_ rules: [MessageRule]) {
		let configurations = rules.map { PropertyListValue.dictionary($0.dictionaryValue) }
		savedConfigurations = configurations
		Preferences.Rules.messageRules.propertyListValue = .array(configurations)
		engine.rulesDidChange()
	}
}
