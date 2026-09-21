// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

extension TranscriptView {
	/// Re-evaluates visibility without discarding the source messages. Only rows
	/// whose presentation changed are rewritten in the native text storage.
	func refreshFolding() {
		let session = viewController?.associatedSession
		let eventDisplay = viewController?.associatedConversation?.config.generalEventMessageDisplay ?? .show
		let hasMutedUsers = session?.config.ignoreList.contains(where: \.muteMessages) == true
		guard eventDisplay != .show || hasMutedUsers || !document.folding.presentations.isEmpty else { return }
		let nicknames = hasMutedUsers ? Set(document.lines.compactMap(\.nickname)) : []
		let muted = Set(nicknames.filter { session?.isUserMuted(nickname: $0) == true })
		let changed = document.folding.update(
			rows: document.lines,
			generalEventDisplay: eventDisplay,
			mutedNicknames: muted,
			caseMapping: session?.supportInfo.caseMapping ?? .rfc1459
		)
		redrawFoldedLines(changed)
	}

	func reloadFolding() {
		performEditingBatch { refreshFolding() }
	}

	func toggleFoldedGroup(_ lineNumber: String) {
		followsBottom = false
		scrollsToBottomOnLayout = false
		performEditingBatch {
			redrawFoldedLines(document.folding.toggle(summaryLineNumber: lineNumber))
		}
	}

	func revealFoldedLine(_ lineNumber: String) {
		performEditingBatch {
			redrawFoldedLines(document.folding.reveal(lineNumber: lineNumber))
		}
	}

	private func redrawFoldedLines(_ lineNumbers: Set<String>) {
		let indices = lineNumbers.compactMap { document.index(ofLine: $0) }
		guard let first = indices.min(), let last = indices.max(), let storage = textView.textStorage else { return }
		let changedRange = first ..< (last + 1)
		let origin = document.location(ofLineAt: first)
		let range = NSRange(location: origin, length: document.location(ofLineAt: last + 1) - origin)
		let rendered = NSMutableAttributedString()
		var lengths: [Int] = []
		beginNicknameColorBatch()
		for index in changedRange {
			let line = renderVisibleLine(document[index])
			lengths.append(line.length)
			rendered.append(line)
		}
		storage.replaceCharacters(in: range, with: rendered)
		document.noteLinesRedrawn(in: changedRange, lengths: lengths)
		updateLayoutAfterEdit()
	}

	func renderVisibleLine(_ line: TranscriptRow) -> NSAttributedString {
		switch document.folding.presentations[line.lineNumber] {
		case .hidden:
			return renderFoldMarkers(line)
		case let .summary(kind, count, expanded):
			let result = renderFoldSummary(line, kind: kind, count: count, expanded: expanded)
			if expanded {
				var content = line
				content.markers = []
				result.append(render(content))
			}
			return result
		case nil:
			return render(line)
		}
	}

	private func renderFoldSummary(
		_ line: TranscriptRow,
		kind: TranscriptFoldKind,
		count: Int,
		expanded: Bool
	) -> NSMutableAttributedString {
		let result = renderFoldMarkers(line)
		let theme = AppServices.theme.theme
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineSpacing = theme.lineSpacing
		paragraph.paragraphSpacing = theme.messageSpacing
		paragraph.firstLineHeadIndent = theme.horizontalPadding
		paragraph.headIndent = theme.horizontalPadding
		paragraph.tailIndent = -theme.horizontalPadding
		var attributes: [NSAttributedString.Key: Any] = [
			.font: effectiveFont(AppServices.theme),
			.foregroundColor: themeColor(theme.palette.eventText),
			.paragraphStyle: paragraph,
			.transcriptLineNumber: line.lineNumber,
			.transcriptSelectionSegment: "fold-summary",
			.transcriptFoldLineNumber: line.lineNumber,
		]
		if case let .mutedUser(_, nickname) = kind {
			attributes[.transcriptLineNickname] = nickname
		}
		// A native link supports pointer, keyboard and VoiceOver activation.
		// Its target is consumed by the text delegate and never opened externally.
		if let link = URL(string: "glasstual-transcript:fold") {
			attributes[.link] = link
		}
		let caption = switch (kind, expanded) {
		case (.generalEvents, true):
			String(localized: .Transcript.collapseGeneralEvents(count))
		case (.generalEvents, false):
			String(localized: .Transcript.expandGeneralEvents(count))
		case let (.mutedUser(_, nickname), true):
			String(localized: .Transcript.collapseMutedMessages(count, TranscriptTextSanitizer.singleLine(nickname)))
		case let (.mutedUser(_, nickname), false):
			String(localized: .Transcript.expandMutedMessages(count, TranscriptTextSanitizer.singleLine(nickname)))
		}
		result.append(NSAttributedString(string: caption, attributes: attributes))
		attributes.removeValue(forKey: .link)
		attributes.removeValue(forKey: .transcriptFoldLineNumber)
		result.append(NSAttributedString(string: "\n", attributes: attributes))
		return result
	}

	private func renderFoldMarkers(_ line: TranscriptRow) -> NSMutableAttributedString {
		let result = NSMutableAttributedString()
		for marker in line.markers {
			let start = result.length
			result.append(render(marker, lineNumber: line.lineNumber))
			result.addAttribute(.transcriptSelectionSegment, value: marker.selectionSegment,
			                    range: NSRange(location: start, length: result.length - start))
		}
		return result
	}

	func foldMenuItems(for lineNumber: String) -> [NSMenuItem] {
		guard case let .summary(_, _, expanded) = document.folding.presentations[lineNumber] else { return [] }
		let item = NSMenuItem(
			title: String(localized: expanded ? .Transcript.collapseMessages : .Transcript.expandMessages),
			action: #selector(toggleFoldedGroupFromMenu(_:)), keyEquivalent: ""
		)
		item.target = self
		item.representedObject = lineNumber
		item.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
		return [item]
	}

	@objc private func toggleFoldedGroupFromMenu(_ sender: NSMenuItem) {
		guard let lineNumber = sender.representedObject as? String else { return }
		toggleFoldedGroup(lineNumber)
	}

	func activateSelectedFold() -> Bool {
		let selection = textView.selectedRange()
		guard selection.length == 0, let storage = textView.textStorage,
		      selection.location < storage.length,
		      let lineNumber = storage.attribute(.transcriptFoldLineNumber, at: selection.location, effectiveRange: nil) as? String
		else { return false }
		toggleFoldedGroup(lineNumber)
		return true
	}
}
