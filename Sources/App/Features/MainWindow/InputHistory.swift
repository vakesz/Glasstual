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

private let inputHistoryMaximumCount = 100

/// Which history buffer the input field is typing into. The global scope used
/// to be the magic key "TLOInputHistoryDefaultObject" in the same dictionary as
/// the per-item buffers, where a tree item with that identifier would have
/// collided with it.
enum InputHistoryScope: Hashable, Sendable {
	case global
	case item(String)
}

@MainActor
private final class InputHistoryObject {
	private var historyBuffer: [NSAttributedString] = []
	private var historyBufferPosition = 0
	var lastHistoryItem: NSAttributedString?

	func add(_ string: NSAttributedString) {
		guard string.length > 0 else {
			return
		}

		if historyBuffer.last?.string != string.string {
			addToBuffer(string)
		}

		historyBufferPosition = historyBuffer.count
	}

	func up(_ string: NSAttributedString) -> NSAttributedString? {
		if string.length > 0, entryAtBufferPosition()?.string != string.string {
			addToBuffer(string)
		}

		historyBufferPosition -= 1

		if historyBufferPosition < 0 {
			historyBufferPosition = 0
		} else if historyBuffer.indices.contains(historyBufferPosition) {
			return historyBuffer[historyBufferPosition]
		}

		return nil
	}

	func down(_ string: NSAttributedString) -> NSAttributedString? {
		guard string.length > 0 else {
			historyBufferPosition = historyBuffer.count

			return nil
		}

		if entryAtBufferPosition()?.string != string.string {
			addToBuffer(string)

			return NSAttributedString(string: "")
		}

		historyBufferPosition += 1

		return entryAtBufferPosition() ?? NSAttributedString(string: "")
	}

	func copied() -> InputHistoryObject {
		let copy = InputHistoryObject()
		copy.historyBuffer = historyBuffer
		copy.historyBufferPosition = historyBufferPosition
		copy.lastHistoryItem = lastHistoryItem.map(NSAttributedString.init(attributedString:))

		return copy
	}

	private func addToBuffer(_ string: NSAttributedString) {
		historyBuffer.append(NSAttributedString(attributedString: string))

		if historyBuffer.count > inputHistoryMaximumCount {
			historyBuffer.removeFirst()
		}
	}

	private func entryAtBufferPosition() -> NSAttributedString? {
		guard historyBuffer.indices.contains(historyBufferPosition) else {
			return nil
		}

		return historyBuffer[historyBufferPosition]
	}
}

/** The input history follows the focused view, so it lives where the text field
 does: on the main actor. That is what makes the plain stored state safe. */
@objc(TLOInputHistory)
@MainActor
public final class InputHistory: NSObject {
	private weak var window: TVCMainWindow?
	private var historyObjects: [InputHistoryScope: InputHistoryObject] = [:]
	private var currentTreeItem: String?

	@available(*, unavailable)
	override public convenience init() {
		fatalError("Use init(window:)")
	}

	@objc(initWithWindow:)
	public init(window: TVCMainWindow) {
		self.window = window

		super.init()
	}

	@objc(destroy:)
	public func destroy(_ treeItem: IRCTreeItem) {
		guard TextualPreferences.inputHistoryIsChannelSpecific() else {
			return
		}

		if let client = treeItem as? IRCClient {
			for channel in client.channelList {
				destroy(channel)
			}
		}

		let itemIdentifier = treeItem.uniqueIdentifier
		historyObjects.removeValue(forKey: .item(itemIdentifier))

		if currentTreeItem == itemIdentifier {
			currentTreeItem = nil
		}
	}

	@objc(moveFocusTo:)
	public func moveFocus(to treeItem: IRCTreeItem) {
		guard TextualPreferences.inputHistoryIsChannelSpecific(),
		      let textView = window?.inputTextField as? TextViewWithIRCFormatter
		else {
			return
		}

		if let oldObject = currentObjectForFocusedTreeView() {
			oldObject.lastHistoryItem = NSAttributedString(attributedString: textView.attributedStringValue)
		}

		currentTreeItem = treeItem.uniqueIdentifier

		if let lastHistoryItem = currentObjectForFocusedTreeView()?.lastHistoryItem {
			textView.attributedStringValue = lastHistoryItem
		} else {
			textView.stringValue = ""
		}
	}

	@objc public func noteInputHistoryObjectScopeDidChange() {
		if TextualPreferences.inputHistoryIsChannelSpecific() {
			for client in AppController.shared.world.clientList {
				applyGlobalHistory(to: client.uniqueIdentifier)

				for channel in client.channelList {
					applyGlobalHistory(to: channel.uniqueIdentifier)
				}
			}

			historyObjects.removeValue(forKey: .global)
		} else {
			historyObjects.removeAll()
			currentTreeItem = nil
		}
	}

	@objc(add:)
	public func add(_ string: NSAttributedString) {
		currentObjectForFocusedTreeView()?.add(string)
	}

	@objc(up:)
	public func up(_ string: NSAttributedString) -> NSAttributedString? {
		currentObjectForFocusedTreeView()?.up(string)
	}

	@objc(down:)
	public func down(_ string: NSAttributedString) -> NSAttributedString? {
		currentObjectForFocusedTreeView()?.down(string)
	}

	private func applyGlobalHistory(to itemIdentifier: String) {
		guard let globalObject = historyObjects[.global] else {
			return
		}

		let newObject = globalObject.copied()
		newObject.lastHistoryItem = nil
		historyObjects[.item(itemIdentifier)] = newObject
	}

	/// `nil` when history is channel-specific and nothing is focused.
	var currentScope: InputHistoryScope? {
		guard TextualPreferences.inputHistoryIsChannelSpecific() else {
			return .global
		}

		return currentTreeItem.map(InputHistoryScope.item)
	}

	private func currentObjectForFocusedTreeView() -> InputHistoryObject? {
		guard let scope = currentScope else {
			return nil
		}

		if let currentObject = historyObjects[scope] {
			return currentObject
		}

		let currentObject = InputHistoryObject()
		historyObjects[scope] = currentObject

		return currentObject
	}
}
