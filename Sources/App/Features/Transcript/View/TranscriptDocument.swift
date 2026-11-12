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
 `storedLineStarts.count == lines.count + 1`.

 The ordinals are what keep the indexes stable. Lines arrive at either end and
 leave from the top, so an ordinal is fixed for as long as its line is held;
 ``firstLineOrdinal`` is the ordinal of `lines[0]`, and an index is the
 difference. Nothing is renumbered when older lines are put in front or the
 oldest are trimmed. The one exception is history recovered from the server,
 which goes between two held lines: the lines after it are renumbered then,
 once per recovered run. */
struct TranscriptDocument {
	var folding = TranscriptFoldingState()
	/// The rows the transcript is showing, oldest first.
	private(set) var lines: [TranscriptRow] = []

	/** Where each line begins in the text storage, in the order ``lines`` holds
	 them, with the end of the document at the end.

	 It is what lets an edit reach one line's characters without rewriting the
	 document around them, and it is stored rather than summed per lookup:
	 restoring the selection after a single append asks for two of these, and
	 summing the lengths before a line made each answer a walk of the buffer. */
	private var storedLineStarts: [Int] = [0]

	/// Where each line begins, plus the end of the document. Built on demand;
	/// the document itself reads through ``location(ofLineAt:)``.
	var lineStarts: [Int] {
		storedLineStarts.map { $0 + lineStartBias }
	}

	/// Added to every stored start. Retiring the oldest lines moves every
	/// remaining line by the same amount, which this absorbs in one step
	/// instead of rewriting the whole array.
	private var lineStartBias = 0

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
	private(set) var messageLineOrdinals: [MessageIdentifierKey: [Int]] = [:]

	/// The ordinal of `lines[0]`.
	private(set) var firstLineOrdinal = 0

	/// The decoded images, and the placeholders still waiting for the reader,
	/// each line drew, keyed by line number. Written only from here, beside the
	/// lines the keys name: a table a caller could edit on its own is a table
	/// that can outlive the line it belongs to.
	private(set) var inlineMedia: [String: [TranscriptInlineMedia]] = [:]

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
		messageLineOrdinals[MessageIdentifierKey(identifier)]
	}

	/// Where a line begins in the text storage. `lines.count` names the end of
	/// the document, which is where an append starts writing.
	func location(ofLineAt index: Int) -> Int {
		storedLineStarts[index] + lineStartBias
	}

	/// How many characters a line drew.
	func length(ofLineAt index: Int) -> Int {
		storedLineStarts[index + 1] - storedLineStarts[index]
	}

	func range(ofLine lineNumber: String) -> NSRange? {
		guard let index = index(ofLine: lineNumber) else { return nil }
		return NSRange(location: location(ofLineAt: index), length: length(ofLineAt: index))
	}

	/// The characters one message drew, across every row it is spread over, or
	/// nothing where no row of it is in the document.
	func range(ofMessage identifier: String) -> NSRange? {
		guard let ordinals = messageLineOrdinals[MessageIdentifierKey(identifier)] else { return nil }
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

	/** How many of the oldest lines to drop now, or zero.

	 The buffer may run over its ceiling by an eighth of the reader's setting
	 before it is cut back to the ceiling. Removing characters from the top makes TextKit shift the range of every
	 paragraph it holds, so trimming one line per batch cost a pass over the
	 whole transcript for every batch a busy channel received; trimming in steps
	 spreads that pass over many lines. */
	func overflow(followsBottom: Bool) -> Int {
		let excess = lines.count - effectiveBufferLimit(followsBottom: followsBottom)
		return excess > bufferLimit / 8 ? excess : 0
	}

	/// How many more lines the document may hold at all, whatever the reader's
	/// buffer setting: the hard ceiling a prepend is measured against.
	var roomBeforeCeiling: Int {
		TranscriptBufferLimits.validLimits.upperBound - lines.count
	}

	// MARK: - Editing

	/// Empties the document. The caller empties the text storage to match.
	mutating func removeAll() {
		folding.reset()
		lines.removeAll()
		storedLineStarts = [0]
		lineStartBias = 0
		highlightedLineCount = 0
		lineOrdinals.removeAll()
		messageLineOrdinals.removeAll()
		firstLineOrdinal = 0
		inlineMedia.removeAll()
		scrollbackAllowance = 0
		checkInvariant()
	}

	/// Takes the lines back out and leaves the indexes empty, for a rebuild that
	/// re-inserts every one of them. The caller empties the storage to match.
	mutating func takeLinesForRebuild() -> [TranscriptRow] {
		let retained = lines
		lines.removeAll(keepingCapacity: true)
		storedLineStarts = [0]
		lineStartBias = 0
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
	 arrive in front of the first ordinal or after the last; recovered history
	 arrives between two lines, and the lines after it take new ordinals. */
	mutating func insert(_ newLines: [TranscriptRow], at index: Int, starts: [Int], totalLength: Int) {
		precondition((0 ... lines.count).contains(index))
		precondition(starts.count == newLines.count)
		guard newLines.isEmpty == false else { return }
		if index == 0 {
			firstLineOrdinal -= newLines.count
		} else if index < lines.count {
			renumberOrdinals(from: firstLineOrdinal + index, by: newLines.count)
		}
		let firstOrdinal = firstLineOrdinal + index
		lines.insert(contentsOf: newLines, at: index)
		storedLineStarts.insert(contentsOf: starts.map { $0 - lineStartBias }, at: index)
		shiftLineStarts(after: index + newLines.count - 1, by: totalLength)
		for (offset, line) in newLines.enumerated() {
			let ordinal = firstOrdinal + offset
			for identifier in line.identifiers where lineOrdinals[identifier] == nil {
				lineOrdinals[identifier] = ordinal
			}
			indexMessage(of: line, ordinal: ordinal)
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
			if let messageIdentifier = line.messageIdentifier, messageLineOrdinals[MessageIdentifierKey(messageIdentifier)] == nil {
				retiredMessageIdentifiers.append(messageIdentifier)
			}
			inlineMedia.removeValue(forKey: line.lineNumber)
			for marker in line.markers {
				retiredMarkers[marker.selectionSegment] = marker
			}
		}
		highlightedLineCount -= lines[indices].filter(\.body.isHighlight).count
		lines.removeSubrange(indices)
		storedLineStarts.removeSubrange(indices)
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

	/// Reindexes a contiguous batch once, including rows that drew no text.
	/// Expanding a large group must not shift the document once per message.
	mutating func noteLinesRedrawn(in indices: Range<Int>, lengths: [Int]) {
		precondition(indices.count == lengths.count)
		let previousEnd = location(ofLineAt: indices.upperBound)
		var location = location(ofLineAt: indices.lowerBound)
		for (index, length) in zip(indices, lengths) {
			storedLineStarts[index] = location - lineStartBias
			location += length
		}
		shiftLineStarts(after: indices.upperBound - 1, by: location - previousEnd)
		checkInvariant()
	}

	/// Applies a delivery receipt. `true` when the line exists and the caller
	/// has to redraw it.
	mutating func updateDelivery(_ update: TranscriptDeliveryUpdate) -> Int? {
		guard let index = index(ofLine: update.lineNumber) else { return nil }
		unindexMessage(of: lines[index], ordinal: firstLineOrdinal + index)
		highlightedLineCount -= lines[index].body.isHighlight ? 1 : 0
		lines[index] = update.applying(to: lines[index])
		highlightedLineCount += lines[index].body.isHighlight ? 1 : 0
		indexMessage(of: lines[index], ordinal: firstLineOrdinal + index)
		if update.replacement != nil {
			inlineMedia.removeValue(forKey: update.lineNumber)
		}
		return index
	}

	/// Replaces every line that carries `messageIdentifier` with the deleted
	/// placeholder, and answers with the indices the caller has to redraw. A
	/// line that is already the placeholder is left alone.
	mutating func redactMessage(messageIdentifier: String, placeholder: String) -> [Int] {
		var changed: [Int] = []
		for ordinal in messageLineOrdinals[MessageIdentifierKey(messageIdentifier)] ?? [] {
			let index = ordinal - firstLineOrdinal
			guard lines.indices.contains(index),
			      lines[index].lineType != .redacted || lines[index].body.plainText != placeholder
			else { continue }
			highlightedLineCount -= lines[index].body.isHighlight ? 1 : 0
			lines[index].redact(placeholder: placeholder)
			inlineMedia.removeValue(forKey: lines[index].lineNumber)
			changed.append(index)
		}
		return changed
	}

	/// Merges reactions into every line that carries `messageIdentifier`, and
	/// answers with the indices the caller has to redraw. A redacted line
	/// carries none: its message is gone.
	mutating func mergeReactions(_ reactions: [String: [String]], messageIdentifier: String) -> [Int] {
		var changed: [Int] = []
		for ordinal in messageLineOrdinals[MessageIdentifierKey(messageIdentifier)] ?? [] {
			let index = ordinal - firstLineOrdinal
			guard lines.indices.contains(index), lines[index].lineType != .redacted else { continue }
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

	/// Gives the line at `index` the date marker `caption`, or none. `true`
	/// when that changed the line and the caller has to redraw it.
	mutating func setDateMarker(_ caption: String?, at index: Int) -> Bool {
		lines[index].setDateMarker(caption)
	}

	/// Records a decoded image against the line that asked for it, in place of
	/// the placeholder that stood for it. `nil` when the line has already been
	/// trimmed, or already carries this image.
	mutating func addInlineImage(_ image: CachedTranscriptImage, to lineNumber: String) -> Int? {
		guard let index = index(ofLine: lineNumber), lines[index].lineNumber == lineNumber else { return nil }
		var media = inlineMedia[lineNumber] ?? []
		if let existing = media.firstIndex(where: { $0.linkIdentifier == image.linkIdentifier }) {
			guard media[existing].placeholder != nil else { return nil }
			media[existing] = .image(image)
		} else {
			media.append(.image(image))
		}
		inlineMedia[lineNumber] = media
		return index
	}

	/// Records a placeholder for a link whose image waits for the reader. `nil`
	/// when the line has been trimmed, or already draws something for the link.
	mutating func addInlineImagePlaceholder(_ placeholder: TranscriptInlineImagePlaceholder) -> Int? {
		let lineNumber = placeholder.key.lineNumber
		guard let index = index(ofLine: lineNumber), lines[index].lineNumber == lineNumber else { return nil }
		var media = inlineMedia[lineNumber] ?? []
		guard media.contains(where: { $0.linkIdentifier == placeholder.key.linkIdentifier }) == false else { return nil }
		media.append(.placeholder(placeholder))
		inlineMedia[lineNumber] = media
		return index
	}

	/// The placeholder `key` names, while the line still draws one there.
	func inlineImagePlaceholder(_ key: TranscriptInlineImagePlaceholder.Key) -> TranscriptInlineImagePlaceholder? {
		inlineMedia[key.lineNumber]?.lazy.compactMap(\.placeholder).first { $0.key == key }
	}

	/// Moves a placeholder to `state`, and answers with the index of the line
	/// to redraw; `nil` when there is no such placeholder or nothing changed.
	mutating func setInlineImagePlaceholderState(
		_ state: TranscriptInlineImagePlaceholder.State,
		for key: TranscriptInlineImagePlaceholder.Key
	) -> Int? {
		guard let index = index(ofLine: key.lineNumber), var media = inlineMedia[key.lineNumber],
		      let position = media.firstIndex(where: { $0.placeholder?.key == key }),
		      var placeholder = media[position].placeholder, placeholder.state != state
		else { return nil }
		placeholder.state = state
		media[position] = .placeholder(placeholder)
		inlineMedia[key.lineNumber] = media
		return index
	}

	/// Takes a placeholder away, and answers with the index of the line to
	/// redraw; `nil` when there is no such placeholder.
	mutating func removeInlineImagePlaceholder(_ key: TranscriptInlineImagePlaceholder.Key) -> Int? {
		guard let index = index(ofLine: key.lineNumber), var media = inlineMedia[key.lineNumber],
		      let position = media.firstIndex(where: { $0.placeholder?.key == key })
		else { return nil }
		media.remove(at: position)
		inlineMedia[key.lineNumber] = media.isEmpty ? nil : media
		return index
	}

	// MARK: - Indexes

	/// Keeps each message's ordinals ascending, wherever its line went in.
	private mutating func indexMessage(of line: TranscriptRow, ordinal: Int) {
		guard let identifier = line.messageIdentifier else { return }
		var ordinals = messageLineOrdinals[MessageIdentifierKey(identifier)] ?? []
		ordinals.insert(ordinal, at: ordinals.firstIndex { $0 > ordinal } ?? ordinals.endIndex)
		messageLineOrdinals[MessageIdentifierKey(identifier)] = ordinals
	}

	/// Moves every ordinal from `boundary` on by `count`, for lines that go
	/// in between two held lines.
	private mutating func renumberOrdinals(from boundary: Int, by count: Int) {
		lineOrdinals = lineOrdinals.mapValues { $0 >= boundary ? $0 + count : $0 }
		messageLineOrdinals = messageLineOrdinals.mapValues { ordinals in
			ordinals.map { $0 >= boundary ? $0 + count : $0 }
		}
	}

	private mutating func unindexMessage(of line: TranscriptRow, ordinal: Int) {
		guard let identifier = line.messageIdentifier else { return }
		messageLineOrdinals[MessageIdentifierKey(identifier)]?.removeAll { $0 == ordinal }
		if messageLineOrdinals[MessageIdentifierKey(identifier)]?.isEmpty == true {
			messageLineOrdinals.removeValue(forKey: MessageIdentifierKey(identifier))
		}
	}

	/// Moves every line after `index` by `delta`, which is what an edit that
	/// changed the length of one line leaves to do.
	private mutating func shiftLineStarts(after index: Int, by delta: Int) {
		guard delta != 0 else { return }
		guard index >= 0 else {
			lineStartBias += delta
			return
		}
		for position in (index + 1) ..< storedLineStarts.count {
			storedLineStarts[position] += delta
		}
	}

	/// Every edit ends here. The two arrays describe the same text, so one
	/// growing without the other is a document that would read the wrong
	/// characters for a line rather than merely draw one wrong.
	private func checkInvariant() {
		precondition(storedLineStarts.count == lines.count + 1, "Transcript line starts and lines disagree")
	}
}
