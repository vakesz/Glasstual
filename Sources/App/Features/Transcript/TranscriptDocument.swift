// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The lines a transcript holds, where each one begins in the text, and the
 indexes that reach a line without walking the buffer.

 It owns no text storage and no view: the view renders characters and splices
 them, then tells the document how long each line came out. That is what lets
 the ordinal scheme, the identifier indexes and the trim be driven -- and
 checked -- without an `NSView`, and it is why every mutation here ends by
 asserting the one invariant that ties the two arrays together:
 `lineStarts.count == lines.count + 1`.

 The ordinals are what keep the indexes stable. Lines only ever arrive at
 either end and leave from the top, so an ordinal is fixed for as long as its
 line is held; ``firstLineOrdinal`` is the ordinal of `lines[0]`, and an index
 is the difference. Nothing is renumbered when older lines are put in front or
 the oldest are trimmed. */
struct TranscriptDocument {
	/// The rows the transcript is showing, oldest first.
	private(set) var lines: [TranscriptRow] = []

	/** Where each line begins in the text storage, in the order ``lines`` holds
	 them, with the end of the document at the end.

	 It is what lets an edit reach one line's characters without rewriting the
	 document around them, and it is stored rather than summed per lookup:
	 restoring the selection after a single append asks for two of these, and
	 summing the lengths before a line made each answer a walk of the buffer. */
	private(set) var lineStarts: [Int] = [0]

	/// How many lines on screen are highlights. Counted as the document is
	/// edited because the menu asks on every validation pass, and the answer
	/// used to be a walk of the whole scrollback.
	private(set) var highlightedLineCount = 0

	/** Where each identifier the document answers to sits.

	 A row restored from storage answers to two: the history row it came back
	 from and the line number it was printed with. Both are held, which is what
	 keeps a message the reader has already seen from being drawn again beside
	 its restored self. */
	private(set) var lineOrdinals: [String: Int] = [:]

	/// The ordinals of the lines that carry each message identifier, oldest
	/// first, for the reactions addressed to a message.
	private(set) var messageLineOrdinals: [String: [Int]] = [:]

	/// The ordinal of `lines[0]`.
	private(set) var firstLineOrdinal = 0

	/// The decoded images each line drew, keyed by line number. Written only
	/// from here, beside the lines the keys name: a table a caller could edit
	/// on its own is a table that can outlive the line it belongs to.
	private(set) var inlineImages: [String: [CachedTranscriptImage]] = [:]

	/// How many lines the reader asked to keep.
	var bufferLimit = TranscriptBufferLimits.defaultHardLimit

	/** Older lines pulled in while the reader follows the end, which raise the
	 buffer's ceiling so the trim after the prepend does not take them straight
	 back out. Scrollback the reader loads by scrolling back needs none: nothing
	 is trimmed from the top while they read. */
	var scrollbackAllowance = 0

	// MARK: - Reading

	var isEmpty: Bool {
		lines.isEmpty
	}

	var count: Int {
		lines.count
	}

	subscript(index: Int) -> TranscriptRow {
		lines[index]
	}

	var indices: Range<Int> {
		lines.indices
	}

	/// The index of the line `identifier` names, under either identifier a
	/// restored row answers to.
	func index(ofLine identifier: String) -> Int? {
		guard let ordinal = lineOrdinals[identifier] else { return nil }
		let index = ordinal - firstLineOrdinal
		return lines.indices.contains(index) ? index : nil
	}

	func contains(identifier: String) -> Bool {
		lineOrdinals[identifier] != nil
	}

	func ordinals(ofMessage identifier: String) -> [Int]? {
		messageLineOrdinals[identifier]
	}

	/// Where a line begins in the text storage. `lines.count` names the end of
	/// the document, which is where an append starts writing.
	func location(ofLineAt index: Int) -> Int {
		lineStarts[index]
	}

	/// How many characters a line drew.
	func length(ofLineAt index: Int) -> Int {
		lineStarts[index + 1] - lineStarts[index]
	}

	func range(ofLine lineNumber: String) -> NSRange? {
		guard let index = index(ofLine: lineNumber) else { return nil }
		return NSRange(location: location(ofLineAt: index), length: length(ofLineAt: index))
	}

	/// The characters one message drew, across every row it is spread over, or
	/// nothing where no row of it is in the document.
	func range(ofMessage identifier: String) -> NSRange? {
		guard let ordinals = messageLineOrdinals[identifier] else { return nil }
		let indices = ordinals.map { $0 - firstLineOrdinal }.filter { lines.indices.contains($0) }
		guard let first = indices.min(), let last = indices.max() else { return nil }
		let start = location(ofLineAt: first)
		return NSRange(location: start, length: location(ofLineAt: last) + length(ofLineAt: last) - start)
	}

	/// The lines of `newLines` the document does not already hold, in order and
	/// without repeats within the batch itself.
	func accepting(_ newLines: [TranscriptRow]) -> [TranscriptRow] {
		var batch = Set<String>()
		return newLines.filter {
			lineOrdinals[$0.lineNumber] == nil && batch.insert($0.lineNumber).inserted
		}
	}

	/** The ceiling the buffer is trimmed to.

	 While the reader follows the end it is what they asked for, widened by any
	 scrollback pulled in since. While they are reading back it is the largest
	 scrollback the setting allows: every line trimmed from the top then is
	 one the reader may be looking at, and trimming it moved the text under them
	 and pulled the viewport into the range that fetches more history -- so a
	 busy conversation dropped what the reader had loaded and fetched it again, once
	 per message. The scrollback comes back down when they return to the end. */
	func effectiveBufferLimit(followsBottom: Bool) -> Int {
		let ceiling = TranscriptBufferLimits.validLimits.upperBound
		return followsBottom ? min(bufferLimit + scrollbackAllowance, ceiling) : ceiling
	}

	/// How many of the oldest lines no longer fit, or zero.
	func overflow(followsBottom: Bool) -> Int {
		max(0, lines.count - effectiveBufferLimit(followsBottom: followsBottom))
	}

	/// How many more lines the document may hold at all, whatever the reader's
	/// buffer setting: the hard ceiling a prepend is measured against.
	var roomBeforeCeiling: Int {
		TranscriptBufferLimits.validLimits.upperBound - lines.count
	}

	// MARK: - Editing

	/// Empties the document. The caller empties the text storage to match.
	mutating func removeAll() {
		lines.removeAll()
		lineStarts = [0]
		highlightedLineCount = 0
		lineOrdinals.removeAll()
		messageLineOrdinals.removeAll()
		firstLineOrdinal = 0
		inlineImages.removeAll()
		scrollbackAllowance = 0
		checkInvariant()
	}

	/// Takes the lines back out and leaves the indexes empty, for a rebuild that
	/// re-inserts every one of them. The caller empties the storage to match.
	mutating func takeLinesForRebuild() -> [TranscriptRow] {
		let retained = lines
		lines.removeAll(keepingCapacity: true)
		lineStarts = [0]
		highlightedLineCount = 0
		lineOrdinals.removeAll()
		messageLineOrdinals.removeAll()
		firstLineOrdinal = 0
		checkInvariant()
		return retained
	}

	/** Records lines the caller has already written into the storage.

	 `starts` is where each one begins and `totalLength` how many characters
	 they drew together, both measured by the caller as it rendered them. Lines
	 arrive at either end: in front of the first ordinal, or after the last. */
	mutating func insert(_ newLines: [TranscriptRow], at index: Int, starts: [Int], totalLength: Int) {
		precondition(index == 0 || index == lines.count)
		precondition(starts.count == newLines.count)
		guard newLines.isEmpty == false else { return }
		if index == 0 {
			firstLineOrdinal -= newLines.count
		}
		let firstOrdinal = firstLineOrdinal + index
		lines.insert(contentsOf: newLines, at: index)
		lineStarts.insert(contentsOf: starts, at: index)
		shiftLineStarts(after: index + newLines.count - 1, by: totalLength)
		/* In front, the new lines' message ordinals come before the ones already
		 held, so they are indexed newest first to keep each list ascending. */
		let ordinals = Array(zip(newLines.indices, newLines))
		for (offset, line) in index == 0 ? ordinals.reversed() : ordinals {
			let ordinal = firstOrdinal + offset
			for identifier in line.identifiers where lineOrdinals[identifier] == nil {
				lineOrdinals[identifier] = ordinal
			}
			indexMessage(of: line, ordinal: ordinal, inFront: index == 0)
		}
		highlightedLineCount += newLines.filter(\.body.isHighlight).count
		checkInvariant()
	}

	/// What a trim leaves the caller to clean up outside the document.
	struct Retirement {
		/// The characters the removed lines drew.
		let characterRange: NSRange
		/// The line numbers they were printed with.
		let lineNumbers: [String]
		/// Message identifiers no line in the document carries any more.
		let messageIdentifiers: [String]
		/// Markers that were drawn on a removed line and now belong on the
		/// oldest line left, if any.
		let carriedMarkers: [TranscriptMarker]
	}

	/// Removes the oldest `indices` lines. Only the oldest: that is the one end
	/// lines ever leave from.
	mutating func remove(_ indices: Range<Int>) -> Retirement {
		precondition(indices.lowerBound == 0)
		let start = location(ofLineAt: indices.lowerBound)
		let removedLength = location(ofLineAt: indices.upperBound) - start
		var retiredMarkers: [String: TranscriptMarker] = [:]
		let retiredLineNumbers = lines[indices].map(\.lineNumber)
		var retiredMessageIdentifiers: [String] = []
		for (offset, line) in zip(indices, lines[indices]) {
			let ordinal = firstLineOrdinal + offset
			for identifier in line.identifiers where lineOrdinals[identifier] == ordinal {
				lineOrdinals.removeValue(forKey: identifier)
			}
			unindexMessage(of: line, ordinal: ordinal)
			if let messageIdentifier = line.messageIdentifier, messageLineOrdinals[messageIdentifier] == nil {
				retiredMessageIdentifiers.append(messageIdentifier)
			}
			inlineImages.removeValue(forKey: line.lineNumber)
			for marker in line.markers {
				retiredMarkers[marker.selectionSegment] = marker
			}
		}
		highlightedLineCount -= lines[indices].filter(\.body.isHighlight).count
		lines.removeSubrange(indices)
		lineStarts.removeSubrange(indices)
		firstLineOrdinal += indices.count
		shiftLineStarts(after: indices.lowerBound - 1, by: -removedLength)
		var carried: [TranscriptMarker] = []
		if lines.isEmpty == false {
			let existing = Set(lines[0].markers.map(\.selectionSegment))
			carried = retiredMarkers.values
				.filter { existing.contains($0.selectionSegment) == false }
				.sorted { $0.selectionSegment < $1.selectionSegment }
			if carried.isEmpty == false {
				lines[0].markers.insert(contentsOf: carried, at: 0)
			}
		}
		checkInvariant()
		return Retirement(
			characterRange: NSRange(location: start, length: removedLength),
			lineNumbers: retiredLineNumbers,
			messageIdentifiers: retiredMessageIdentifiers,
			carriedMarkers: carried
		)
	}

	/// Records that one line was redrawn at a different length.
	mutating func noteLineRedrawn(at index: Int, newLength: Int) {
		shiftLineStarts(after: index, by: newLength - length(ofLineAt: index))
		checkInvariant()
	}

	/// Applies a delivery receipt. `true` when the line exists and the caller
	/// has to redraw it.
	mutating func updateDelivery(_ update: TranscriptDeliveryUpdate) -> Int? {
		guard let index = index(ofLine: update.lineNumber) else { return nil }
		if let messageIdentifier = update.messageIdentifier, messageIdentifier != lines[index].messageIdentifier {
			unindexMessage(of: lines[index], ordinal: firstLineOrdinal + index)
			lines[index].messageIdentifier = messageIdentifier
			indexMessage(of: lines[index], ordinal: firstLineOrdinal + index)
		}
		lines[index].deliveryState = update.state
		lines[index].deliveryFailureReason = update.reason
		return index
	}

	/// Merges reactions into every line that carries `messageIdentifier`, and
	/// answers with the indices the caller has to redraw.
	mutating func mergeReactions(_ reactions: [String: [String]], messageIdentifier: String) -> [Int] {
		var changed: [Int] = []
		for ordinal in messageLineOrdinals[messageIdentifier] ?? [] {
			let index = ordinal - firstLineOrdinal
			guard lines.indices.contains(index) else { continue }
			lines[index].mergeReactions(reactions)
			changed.append(index)
		}
		return changed
	}

	/** Moves the unread boundary, and answers with the indices to redraw.

	 `caption` is the marker's text, which the caller reads from the catalog. */
	mutating func setUnreadMarker(_ mark: UnreadMarker, caption: String) -> [Int] {
		var changed: [Int] = []
		for index in lines.indices where lines[index].markers.contains(where: \.isUnread) {
			lines[index].markers.removeAll(where: \.isUnread)
			changed.append(index)
		}
		let target: Int? = switch mark {
		case .none: nil
		case .latest: lines.indices.last
		/* A line the buffer no longer holds is one it has already trimmed, and
		 it only ever trims the oldest: everything on screen arrived after the
		 line the reader stopped at, so the boundary belongs above all of it.
		 A conversation opened unseen carries its marker the same way. */
		case let .line(identifier): index(ofLine: identifier) ?? lines.indices.first
		case let .after(date): lines.firstIndex { $0.receivedAt >= date && $0.lineType.isConversation }
		}
		if let target {
			lines[target].markers.insert(.unread(caption), at: 0)
			if changed.contains(target) == false {
				changed.append(target)
			}
		}
		return changed.sorted()
	}

	/// Records a decoded image against the line that asked for it. `nil` when
	/// the line has already been trimmed, or already carries this image.
	mutating func addInlineImage(_ image: CachedTranscriptImage, to lineNumber: String) -> Int? {
		guard let index = index(ofLine: lineNumber), lines[index].lineNumber == lineNumber else { return nil }
		var images = inlineImages[lineNumber] ?? []
		guard images.contains(where: { $0.linkIdentifier == image.linkIdentifier }) == false else { return nil }
		images.append(image)
		inlineImages[lineNumber] = images
		return index
	}

	// MARK: - Indexes

	private mutating func indexMessage(of line: TranscriptRow, ordinal: Int, inFront: Bool = false) {
		guard let identifier = line.messageIdentifier else { return }
		if inFront {
			messageLineOrdinals[identifier, default: []].insert(ordinal, at: 0)
		} else {
			messageLineOrdinals[identifier, default: []].append(ordinal)
		}
	}

	private mutating func unindexMessage(of line: TranscriptRow, ordinal: Int) {
		guard let identifier = line.messageIdentifier else { return }
		messageLineOrdinals[identifier]?.removeAll { $0 == ordinal }
		if messageLineOrdinals[identifier]?.isEmpty == true {
			messageLineOrdinals.removeValue(forKey: identifier)
		}
	}

	/// Moves every line after `index` by `delta`, which is what an edit that
	/// changed the length of one line leaves to do.
	private mutating func shiftLineStarts(after index: Int, by delta: Int) {
		guard delta != 0 else { return }
		for position in (index + 1) ..< lineStarts.count {
			lineStarts[position] += delta
		}
	}

	/// Every edit ends here. The two arrays describe the same text, so one
	/// growing without the other is a document that would read the wrong
	/// characters for a line rather than merely draw one wrong.
	private func checkInvariant() {
		precondition(lineStarts.count == lines.count + 1, "Transcript line starts and lines disagree")
	}
}
