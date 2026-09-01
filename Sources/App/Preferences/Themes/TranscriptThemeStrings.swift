/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

nonisolated enum TranscriptThemeStrings { // nonisolated: value
	static func value(_ resource: LocalizedStringResource) -> String {
		String(localized: resource)
	}

	static let background = value(.TranscriptTheme.background)
	static let bubbles = value(.TranscriptTheme.bubbles)
	static let colors = value(.TranscriptTheme.colors)
	static let dark = value(.TranscriptTheme.dark)
	static let delivered = value(.TranscriptTheme.delivered)
	static let eventText = value(.TranscriptTheme.eventText)
	static let exportTheme = value(.TranscriptTheme.exportTheme)
	static let failed = value(.TranscriptTheme.failed)
	static let failure = value(.TranscriptTheme.failure)
	static let highlightBackground = value(.TranscriptTheme.highlightBackground)
	static let highlightText = value(.TranscriptTheme.highlightText)
	static let horizontalPadding = value(.TranscriptTheme.horizontalPadding)
	static let importTheme = value(.TranscriptTheme.importTheme)
	static let incomingBubble = value(.TranscriptTheme.incomingBubble)
	static let invalidDocument = value(.TranscriptTheme.invalidDocument)
	static let layout = value(.TranscriptTheme.layout)
	static let light = value(.TranscriptTheme.light)
	static let lineSpacing = value(.TranscriptTheme.lineSpacing)
	static let lines = value(.TranscriptTheme.lines)
	static let links = value(.TranscriptTheme.links)
	static let messageSpacing = value(.TranscriptTheme.messageSpacing)
	static let otherNicknames = value(.TranscriptTheme.otherNicknames)
	static let outgoingBubble = value(.TranscriptTheme.outgoingBubble)
	static let pending = value(.TranscriptTheme.pending)
	static let primaryText = value(.TranscriptTheme.primaryText)
	static let roleColorNote = value(.TranscriptTheme.roleColorNote)
	static let secondaryText = value(.TranscriptTheme.secondaryText)
	static let showInlineImages = value(.TranscriptTheme.showInlineImages)
	static let themeError = value(.TranscriptTheme.themeError)
	static let themeName = value(.TranscriptTheme.themeName)
	static let transcriptTheme = value(.TranscriptTheme.transcriptTheme)
	static let unreadMarker = value(.TranscriptTheme.unreadMarker)
	static let yourNickname = value(.TranscriptTheme.yourNickname)

	static func unsupportedVersion(_ version: Int) -> String {
		String(localized: .TranscriptTheme.unsupportedVersion(version))
	}
}
