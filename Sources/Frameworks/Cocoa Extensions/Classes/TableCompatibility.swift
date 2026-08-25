/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2020 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import ObjectiveC

private nonisolated(unsafe) var invalidatingSelectionBackgroundKey: UInt8 = 0

extension NSTableView {
	@objc(selectItemAtIndex:)
	func textual_selectItem(at index: UInt) {
		selectRowIndexes(IndexSet(integer: Int(index)), byExtendingSelection: false)
		scrollRowToVisible(Int(index))
	}

	@objc(invalidateBackgroundForSelection)
	func textual_invalidateBackgroundForSelection() {
		textual_invalidatingBackgroundForSelection = true
		defer { textual_invalidatingBackgroundForSelection = false }

		let selectedRows = selectedRowIndexes
		let previouslyAllowedEmptySelection = allowsEmptySelection
		allowsEmptySelection = true
		deselectAll(nil)
		selectRowIndexes(selectedRows, byExtendingSelection: false)
		allowsEmptySelection = previouslyAllowedEmptySelection
	}

	@objc(invalidatingBackgroundForSelection)
	var textual_invalidatingBackgroundForSelection: Bool {
		get {
			(objc_getAssociatedObject(self, &invalidatingSelectionBackgroundKey) as? NSNumber)?.boolValue ?? false
		}
		set {
			objc_setAssociatedObject(
				self,
				&invalidatingSelectionBackgroundKey,
				newValue ? NSNumber(value: true) : nil,
				.OBJC_ASSOCIATION_COPY_NONATOMIC
			)
		}
	}

	@objc(rowBeneathMouse)
	var textual_rowBeneathMouse: Int {
		guard let window else { return -1 }
		return row(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
	}

	@objc(selectionIndexesForProposedSelection:maximumNumberOfSelections:)
	func textual_selectionIndexes(
		forProposedSelection proposedSelection: IndexSet,
		maximumNumberOfSelections maximum: UInt
	) -> IndexSet {
		precondition(maximum > 0)
		guard proposedSelection.count > maximum else { return proposedSelection }
		guard numberOfSelectedRows != maximum else { return selectedRowIndexes }
		return IndexSet(proposedSelection.prefix(Int(maximum)))
	}

	@objc(selectRowIndexes:byExtendingSelection:scrollToSelection:)
	func textual_selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool, scrollToSelection: Bool) {
		selectRowIndexes(indexes, byExtendingSelection: extend)
		if scrollToSelection, let firstIndex = indexes.first {
			scrollRowToVisible(firstIndex)
		}
	}
}

extension NSTableRowView {
	@objc(invalidatingBackgroundForSelection)
	var textual_invalidatingBackgroundForSelection: Bool {
		(superview as? NSTableView)?.textual_invalidatingBackgroundForSelection ?? false
	}
}

extension NSOutlineView {
	@objc(selectedObjects)
	var textual_selectedObjects: [Any] {
		selectedRowIndexes.compactMap { item(atRow: $0) }
	}

	@objc(isGroupItem:)
	func textual_isGroupItem(_ item: Any) -> Bool {
		level(forItem: item) == 0
	}

	@objc(groupItems)
	var textual_groupItems: [Any] {
		(0 ..< numberOfRows).compactMap { row in
			level(forRow: row) == 0 ? item(atRow: row) : nil
		}
	}

	@objc(itemsFromParentGroup:)
	func textual_itemsFromParentGroup(_ item: Any) -> [Any]? {
		textual_items(inGroup: item)
	}

	@objc(itemsInGroup:)
	func textual_items(inGroup candidate: Any) -> [Any]? {
		let groupItem: Any
		if textual_isGroupItem(candidate) {
			groupItem = candidate
		} else if let parent = parent(forItem: candidate) {
			groupItem = parent
		} else {
			return nil
		}

		return (0 ..< numberOfRows).compactMap { row in
			guard let currentItem = item(atRow: row),
			      let parentItem = parent(forItem: currentItem) as AnyObject?,
			      parentItem === groupItem as AnyObject
			else {
				return nil
			}
			return currentItem
		}
	}

	@objc(indexesOfItemsInGroup:)
	func textual_indexesOfItems(inGroup groupItem: Any) -> IndexSet? {
		guard let items = textual_items(inGroup: groupItem),
		      let first = items.first,
		      let last = items.last
		else {
			return nil
		}

		let firstIndex = row(forItem: first)
		let lastIndex = row(forItem: last)
		guard firstIndex >= 0, lastIndex >= firstIndex else { return nil }
		return IndexSet(integersIn: firstIndex ... lastIndex)
	}
}
