/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// The text the transcript itself shows: what a reader hears in place of a
/// picture or a reaction, what an image offers on a right click, and what a
/// link that leaves the browser asks before it opens.
nonisolated enum TranscriptViewStrings { // nonisolated: value
	static var copyImage: String {
		String(localized: .Transcript.copyImage)
	}

	static var saveImage: String {
		String(localized: .Transcript.saveImage)
	}

	static var openImageLink: String {
		String(localized: .Transcript.openImageLink)
	}

	static var copyTopic: String {
		String(localized: .Transcript.copyTopic)
	}

	static func transcriptAccessibility(conversation: String) -> String {
		String(localized: .Transcript.transcriptAccessibility(conversation))
	}

	static var transcriptRoleDescription: String {
		String(localized: .Transcript.transcriptRole)
	}

	/// The question asked before a link is handed to another application.
	/// macOS does not always name the application that would open an address,
	/// and a name that is missing must not be quoted as an empty one.
	static func openLinkTitle(applicationName: String) -> String {
		applicationName.isEmpty
			? String(localized: .Transcript.openLinkInUnknownApplication)
			: String(localized: .Transcript.openLinkInApplication(applicationName))
	}

	static func imageAccessibility(source: String) -> String {
		String(localized: .Transcript.imageAccessibility(source))
	}

	static func reactionAccessibility(emoji: String, count: Int) -> String {
		String(localized: .Transcript.reactionAccessibility(emoji, arg2: count))
	}
}
