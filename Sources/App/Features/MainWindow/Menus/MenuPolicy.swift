/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions

/// Where an insertion landed once it has replaced a selection. The replaced
/// range describes storage that no longer exists, so nothing may be measured
/// against it afterwards.
nonisolated enum MenuInsertionRangePolicy { // nonisolated: value
	static func insertedRange(replacing replaced: NSRange, with insertion: String) -> NSRange {
		NSRange(location: replaced.location, length: insertion.utf16.count)
	}
}

struct MenuServerActionPolicy {
	let canConnect: Bool
	let canConnectWithoutProxy: Bool
	let canDisconnect: Bool
	let canCancelReconnect: Bool

	init(client: Client?) {
		let connected = client.map { $0.isConnecting || $0.isConnected } == true
		let available = client.map { !$0.isQuitting && !$0.isDisconnecting && !$0.isTerminating } == true
		canConnect = available && connected == false
		canConnectWithoutProxy = canConnect && client.map { $0.config.proxyType != .none } == true
		canDisconnect = available && connected
		canCancelReconnect = available && client?.isReconnecting == true
	}
}

/// What a duplicated connection is called. A trailing underscore read as a
/// truncated name; "copy" is the word the Finder uses for the same idea.
nonisolated enum MenuServerNamePolicy { // nonisolated: value
	static func duplicateName(of name: String) -> String {
		ApplicationStrings.duplicatedName(name)
	}
}

enum MenuWindowPolicy {
	static let alertSuppressionPrefix = Preferences.Families.alertSuppression.pattern

	static func appearance(for command: MenuCommand?) -> PreferredAppearance? {
		switch command {
		case .appearanceSystem: .inherited
		case .appearanceLight: .light
		case .appearanceDark: .dark
		default: nil
		}
	}

	static func channelsOrderedBeforeQueries(_ lhs: Channel, _ rhs: Channel) -> Bool {
		/* Both directions have to be answered. Without the second branch a
		 query and a channel compare as "unordered" one way and "ordered" the
		 other, which is not a strict weak ordering and lets sort(by:) produce
		 garbage. */
		if lhs.isChannel != rhs.isChannel {
			return lhs.isChannel
		}
		return lhs.name.lowercased().compare(rhs.name.lowercased()) == .orderedAscending
	}
}

/// Which web-search service the system is set to use, which is what the
/// transcript's Search command has to name. The menu is built with it and
/// validation refreshes it, so the item never says "Google" to someone whose
/// system is set to DuckDuckGo.
@MainActor
enum MenuSearchProvider {
	private static let preferredWebServicesKey = "NSPreferredWebServices"
	private static let webSearchProviderKey = "NSWebServicesProviderWebSearch"
	private static let defaultDisplayNameKey = "NSDefaultDisplayName"
	private static let fallbackName = "Google"

	static var name: String {
		let services = UserDefaults.standard.dictionary(forKey: preferredWebServicesKey)
		let provider = services?[webSearchProviderKey]
			.flatMap(PropertyListValue.init(propertyList:))

		return provider?.dictionary?[defaultDisplayNameKey]?.string ?? fallbackName
	}

	static var menuTitle: String {
		ApplicationStrings.search(with: name)
	}
}

/// Where a Paste command puts what it is carrying.
nonisolated enum MenuPasteTarget: Sendable { // nonisolated: value
	/// Whatever holds the keyboard.
	case firstResponder
	/// The chat input, which is where the main window sends a paste that has no
	/// editable responder of its own to go to.
	case inputField
	/// Nowhere: nothing editable holds the keyboard and there is no input field.
	case none
}

/** The two menu rules that were asking the wrong thing.

 Paste asked whether the main window was key and then validated against the
 chat input, so it read as enabled while the caret was in the toolbar's search
 field or a sheet's field. Change Nickname asked whether the client was
 connected while the action it enables guards on being logged in -- and closes
 the presented sheet on the way -- so choosing it dismissed an unrelated sheet
 and then did nothing. */
@MainActor
enum MenuResponderCommandPolicy {
	/** Paste is a property of the responder that will receive it.

	 The menu item and the action ask the same question of the same three
	 inputs: the item was enabled only for an editable responder while the
	 action fell back to the message field, so ⌘V read as unavailable while the
	 reader was in the transcript -- and the shortcut, which AppKit validates
	 through the item, did nothing at all. */
	static func canPaste(
		pasteboardHasText: Bool,
		responderIsEditableText: Bool,
		responderIsInInputBar: Bool,
		hasInputField: Bool
	) -> Bool {
		guard pasteboardHasText else { return false }
		return pasteTarget(
			responderIsEditableText: responderIsEditableText,
			responderIsInInputBar: responderIsInInputBar,
			hasInputField: hasInputField
		) != .none
	}

	/** Which of the two the paste is aimed at.

	 The same question ``canPaste(pasteboardHasText:responderIsEditableText:responderIsInInputBar:hasInputField:)``
	 answers, asked for the action rather than the menu item: the responder holding
	 the keyboard is the destination, and the chat input is only a fallback. Sending
	 every paste to the input field pulled the focus out of the toolbar's search
	 field or a sheet's field and dropped the text into the conversation
	 instead, so the field is chosen only when the responder belongs to the
	 input bar already, or when nothing editable has the keyboard at all. */
	static func pasteTarget(
		responderIsEditableText: Bool,
		responderIsInInputBar: Bool,
		hasInputField: Bool
	) -> MenuPasteTarget {
		if responderIsEditableText, responderIsInInputBar == false {
			return .firstResponder
		}
		if hasInputField {
			return .inputField
		}
		return responderIsEditableText ? .firstResponder : .none
	}

	/// Change Nickname needs a registered connection, not merely a socket.
	static func canChangeNickname(clientIsLoggedIn: Bool) -> Bool {
		clientIsLoggedIn
	}
}
