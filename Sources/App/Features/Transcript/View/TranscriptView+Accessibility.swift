// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/** What an assistive reader can do with the name under the text cursor.

 A pointer joins a channel or opens a nickname with a double click, and a
 keyboard reader reaches both through the context menu. A screen reader that
 only moves the cursor through the text finds neither, because the runs are
 not links: the text view offers each as a custom action while the selection
 sits on one, and the action does what the double click does. */
extension TranscriptView {
	/// The actions the selection or the caret offers, none while it sits on
	/// plain text.
	func nameAccessibilityActions() -> [NSAccessibilityCustomAction] {
		let target = selectedContextTarget()
		var actions: [NSAccessibilityCustomAction] = []
		if let channelName = target.channelName {
			actions.append(NSAccessibilityCustomAction(
				name: String(localized: .Transcript.joinChannelAction(channelName))
			) { [weak self] in
				guard let self else { return false }
				contextMenuTarget = target
				commands.channelNameDoubleClicked(in: self)
				return true
			})
		}
		if let nickname = target.nickname, nickname.isEmpty == false {
			actions.append(NSAccessibilityCustomAction(
				name: Self.nicknameActionTitle(for: nickname)
			) { [weak self] in
				guard let self else { return false }
				contextMenuTarget = target
				commands.nicknameDoubleClicked(in: self)
				return true
			})
		}
		return actions
	}

	/// Named for what the reader's double-click action will do with the name,
	/// since that is what performing it runs.
	private static func nicknameActionTitle(for nickname: String) -> String {
		switch SettingsKeys.Input.userDoubleClickAction.value {
		case .whois: String(localized: .Transcript.whoisNicknameAction(nickname))
		case .startDirectConversation: String(localized: .Transcript.openConversationNicknameAction(nickname))
		case .insertTextField: String(localized: .Transcript.insertNicknameAction(nickname))
		@unknown default: String(localized: .Transcript.openConversationNicknameAction(nickname))
		}
	}
}

// MARK: - Rotors

/** What a VoiceOver rotor over the transcript moves between.

 The transcript is one text view, so a rotor item is a range of its text: a
 message, a message that mentions the reader, a link, or the separator that
 starts a day. Each comes from the rows' own metadata or the links the text
 carries, never from parsing what was drawn. */
nonisolated enum TranscriptRotorKind: CaseIterable, Sendable {
	case messages
	case mentions
	case links
	case days
}

/// One place a rotor can land on.
nonisolated struct TranscriptRotorItem: Equatable, Sendable {
	var range: NSRange
	var label: String
}

/// Which item a rotor search lands on, from where the reader is now.
nonisolated enum TranscriptRotorSearch {
	/** The index of the item after (or before) `current`, among `items` in
	 document order, or `nil` past either end. With no current item the search
	 starts from the first or the last, as the rotor protocol asks. A filter
	 keeps only the items whose label contains it. */
	static func index(
		in items: [TranscriptRotorItem],
		from current: NSRange?,
		forward: Bool,
		filter: String = ""
	) -> Int? {
		let candidates = items.indices.filter { index in
			filter.isEmpty || items[index].label.localizedStandardContains(filter)
		}
		guard let current, current.location != NSNotFound else {
			return forward ? candidates.first : candidates.last
		}
		if forward {
			return candidates.first { items[$0].range.location > current.location }
		}
		return candidates.last { items[$0].range.location < current.location }
	}
}

extension TranscriptView {
	/// The rotors the transcript offers, built once and kept on the text view.
	func makeAccessibilityRotors() -> [NSAccessibilityCustomRotor] {
		TranscriptRotorKind.allCases.map { kind in
			let delegate = TranscriptRotorDelegate(kind: kind, transcript: self)
			accessibilityRotorDelegates.append(delegate)
			return switch kind {
			case .messages: NSAccessibilityCustomRotor(label: String(localized: .Transcript.rotorMessages), itemSearchDelegate: delegate)
			case .mentions: NSAccessibilityCustomRotor(label: String(localized: .Transcript.rotorMentions), itemSearchDelegate: delegate)
			case .links: NSAccessibilityCustomRotor(rotorType: .link, itemSearchDelegate: delegate)
			case .days: NSAccessibilityCustomRotor(label: String(localized: .Transcript.rotorDays), itemSearchDelegate: delegate)
			}
		}
	}

	/// The items one rotor moves between, in document order.
	func accessibilityRotorItems(_ kind: TranscriptRotorKind) -> [TranscriptRotorItem] {
		guard let storage = textView.textStorage else { return [] }
		let text = storage.string as NSString
		if kind == .links {
			var items: [TranscriptRotorItem] = []
			storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
				guard value != nil else { return }
				items.append(TranscriptRotorItem(range: range, label: text.substring(with: range)))
			}
			return items
		}
		var items: [TranscriptRotorItem] = []
		for index in document.indices {
			let row = document[index]
			let length = document.length(ofLineAt: index)
			let location = document.location(ofLineAt: index)
			guard length > 0, location + length <= storage.length else { continue }
			let range = NSRange(location: location, length: length)
			switch kind {
			case .messages where row.lineType.isRedactableMessage,
			     .mentions where row.lineType.isRedactableMessage && row.body.isHighlight:
				let label = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
				items.append(TranscriptRotorItem(range: range, label: label))
			case .days:
				for case let .date(title) in row.markers {
					items.append(TranscriptRotorItem(range: range, label: title))
				}
			default:
				break
			}
		}
		return items
	}
}

/** Answers one rotor's searches for the transcript.

 Accessibility asks on the main thread, through a protocol AppKit declares
 without isolation; the conformance is the main actor's. */
final class TranscriptRotorDelegate: NSObject, @MainActor NSAccessibilityCustomRotorItemSearchDelegate {
	let kind: TranscriptRotorKind
	private weak var transcript: TranscriptView?

	init(kind: TranscriptRotorKind, transcript: TranscriptView) {
		self.kind = kind
		self.transcript = transcript
	}

	func rotor(
		_: NSAccessibilityCustomRotor,
		resultFor parameters: NSAccessibilityCustomRotor.SearchParameters
	) -> NSAccessibilityCustomRotor.ItemResult? {
		guard let transcript else { return nil }
		let items = transcript.accessibilityRotorItems(kind)
		guard let index = TranscriptRotorSearch.index(
			in: items,
			from: parameters.currentItem?.targetRange,
			forward: parameters.searchDirection == .next,
			filter: parameters.filterString
		) else { return nil }
		let result = NSAccessibilityCustomRotor.ItemResult(targetElement: transcript.textView)
		result.targetRange = items[index].range
		result.customLabel = items[index].label
		return result
	}
}
