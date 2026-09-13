/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

nonisolated enum TranscriptThemeStrings { // nonisolated: value
	static var background: String {
		String(localized: .TranscriptTheme.background)
	}

	static var bubbles: String {
		String(localized: .TranscriptTheme.bubbles)
	}

	static var colors: String {
		String(localized: .TranscriptTheme.colors)
	}

	static var dark: String {
		String(localized: .TranscriptTheme.dark)
	}

	static var delivered: String {
		String(localized: .TranscriptTheme.delivered)
	}

	static var eventText: String {
		String(localized: .TranscriptTheme.eventText)
	}

	static var exportTheme: String {
		String(localized: .TranscriptTheme.exportTheme)
	}

	static var failed: String {
		String(localized: .TranscriptTheme.failed)
	}

	static var failure: String {
		String(localized: .TranscriptTheme.failure)
	}

	static var highlightBackground: String {
		String(localized: .TranscriptTheme.highlightBackground)
	}

	static var highlightText: String {
		String(localized: .TranscriptTheme.highlightText)
	}

	static var horizontalPadding: String {
		String(localized: .TranscriptTheme.horizontalPadding)
	}

	static var importTheme: String {
		String(localized: .TranscriptTheme.importTheme)
	}

	static var incomingBubble: String {
		String(localized: .TranscriptTheme.incomingBubble)
	}

	static var invalidDocument: String {
		String(localized: .TranscriptTheme.invalidDocument)
	}

	static var invalidValues: String {
		String(localized: .TranscriptTheme.invalidValues)
	}

	static var layout: String {
		String(localized: .TranscriptTheme.layout)
	}

	static var light: String {
		String(localized: .TranscriptTheme.light)
	}

	static var lineSpacing: String {
		String(localized: .TranscriptTheme.lineSpacing)
	}

	static var lines: String {
		String(localized: .TranscriptTheme.lines)
	}

	static var links: String {
		String(localized: .TranscriptTheme.links)
	}

	static var messageSpacing: String {
		String(localized: .TranscriptTheme.messageSpacing)
	}

	static var otherNicknames: String {
		String(localized: .TranscriptTheme.otherNicknames)
	}

	static var outgoingBubble: String {
		String(localized: .TranscriptTheme.outgoingBubble)
	}

	static var pending: String {
		String(localized: .TranscriptTheme.pending)
	}

	static var primaryText: String {
		String(localized: .TranscriptTheme.primaryText)
	}

	static var roleColorNote: String {
		String(localized: .TranscriptTheme.roleColorNote)
	}

	static var secondaryText: String {
		String(localized: .TranscriptTheme.secondaryText)
	}

	static var showInlineImages: String {
		String(localized: .TranscriptTheme.showInlineImages)
	}

	static var themeName: String {
		String(localized: .TranscriptTheme.themeName)
	}

	static var timestampText: String {
		String(localized: .TranscriptTheme.timestampText)
	}

	static var transcriptTheme: String {
		String(localized: .TranscriptTheme.transcriptTheme)
	}

	static var unreadMarker: String {
		String(localized: .TranscriptTheme.unreadMarker)
	}

	static var yourNickname: String {
		String(localized: .TranscriptTheme.yourNickname)
	}

	static func unsupportedVersion(_ version: Int) -> String {
		String(localized: .TranscriptTheme.unsupportedVersion(version))
	}
}
