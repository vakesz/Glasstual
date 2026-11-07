// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
import Foundation

/** The plain-text columns a stored line carries so history can be searched
 without unarchiving it.

 `lineData` is an opaque archive, so a predicate cannot look inside it. These
 three columns are written beside it whenever a row is written, replaced or
 redacted, and are backfilled from the archive when an older store is upgraded.

 Only what a person said is searchable: the text of a message, action or
 notice, and its sender. Joins, modes, topics and other events narrate the
 session and have no text here. A redacted line keeps its sender but no text,
 which is what keeps deleted words out of every column the database holds. */
nonisolated struct ScrollbackSearchFields: Sendable, Equatable {
	/// The longest text one row keeps. A message is a few hundred bytes on the
	/// wire; the bound is for a multiline batch, not for ordinary lines.
	static let maximumTextLength = 8192

	static let empty = Self(plainText: "", sender: "")

	let plainText: String
	let sender: String
	/// `plainText` folded for case and diacritics, which is what a query is
	/// folded to before it is compared.
	let searchText: String

	init(plainText: String, sender: String) {
		let bounded = String(plainText.prefix(Self.maximumTextLength))
		self.plainText = bounded
		self.sender = sender
		searchText = Self.folded(bounded)
	}

	init(line: ChatLine) {
		guard line.lineType.isConversation else {
			self = .empty
			return
		}
		let sender = line.nickname ?? ""
		guard line.lineType != .redacted else {
			self.init(plainText: "", sender: sender)
			return
		}
		self.init(plainText: TextFormatting.removingControlCodes(from: line.messageBody), sender: sender)
	}

	/// The same fold a stored `searchText` went through.
	static func folded(_ text: String) -> String {
		text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
	}

	/// The columns a stored row holds, or the empty fields for a row of a
	/// schema that predates them.
	init(managedObject: NSManagedObject) {
		let properties = managedObject.entity.propertiesByName
		guard properties[ScrollbackAttribute.plainText.rawValue] != nil else {
			self = .empty
			return
		}
		self.init(
			plainText: managedObject.value(forKey: ScrollbackAttribute.plainText.rawValue) as? String ?? "",
			sender: managedObject.value(forKey: ScrollbackAttribute.sender.rawValue) as? String ?? ""
		)
	}

	func write(to object: NSManagedObject) {
		object.setValue(plainText, forKey: ScrollbackAttribute.plainText.rawValue)
		object.setValue(sender, forKey: ScrollbackAttribute.sender.rawValue)
		object.setValue(searchText, forKey: ScrollbackAttribute.searchText.rawValue)
	}
}
