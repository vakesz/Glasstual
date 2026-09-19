// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The folder a transcript is filed under, by what kind of conversation it is.

 The strings are folder names on the user's disk, so they stay as they are
 spelled there whatever the Swift vocabulary around them becomes. */
enum TranscriptFolderName {
	static let console = "Console"
	static let channel = "Channels"
	static let direct = "Queries"
}

/** Where an item's transcript is written.

 A pure function of the item: one folder per connection, then one per kind of
 conversation, then one per conversation. Nothing here opens a file, so the
 layout can be asserted without a disk. */
enum TranscriptPath {
	/// The path under the user's transcript folder, or `nil` for an item whose
	/// lines are never written — a console view, or one with no session left.
	static func relative(for item: ChatItem) -> String? {
		let conversation = item.associatedConversation
		if let conversation, conversation.isConsole {
			return nil
		}
		guard let session = item.associatedSession else { return nil }

		let sessionIdentifier = String(session.uniqueIdentifier.prefix(5))
		let sessionName = "\(session.name) (\(sessionIdentifier))".safeFilename
		guard let conversation else {
			return "/\(sessionName)/\(TranscriptFolderName.console)/"
		}
		let conversationName = conversation.name.safeFilename
		if conversation.isChannel {
			return "/\(sessionName)/\(TranscriptFolderName.channel)/\(conversationName)/"
		}
		if conversation.isDirect || conversation.isDirectChat {
			return "/\(sessionName)/\(TranscriptFolderName.direct)/\(conversationName)/"
		}
		return nil
	}

	/// The same path under the folder the user chose, when one has been chosen.
	static func write(for item: ChatItem) -> String? {
		guard let sourcePath = ApplicationPaths.transcriptFolder else { return nil }
		return write(for: item, relativeTo: sourcePath)
	}

	static func write(for item: ChatItem, relativeTo sourcePath: String) -> String? {
		guard let relativePath = relative(for: item) else { return nil }
		return (sourcePath as NSString).appendingPathComponent(relativePath)
	}
}
