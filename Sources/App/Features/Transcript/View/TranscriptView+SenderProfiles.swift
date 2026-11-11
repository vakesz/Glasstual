// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/// What a sender set on the server, as their header draws it.
struct TranscriptSenderProfile {
	/// The display name, already checked against the conversation's nicknames.
	var displayName: String?
	var color: ProfileColor?
	/// The picture, once it arrived and pictures may be shown here.
	var avatar: NSImage?
}

/** The sender's display name and picture beside their nickname.

 The display name and the picture are presentation: they are the
 transcript's own padding, so copying a line yields the nickname as a log
 does, and a screen reader hears one sentence naming both. The nickname is
 always drawn, in its own isolate and a different weight, so a display name
 cannot reorder it or pass for it. */
extension TranscriptView {
	/// The point size of the picture beside a sender.
	static let senderAvatarSize: CGFloat = 16

	/// - Parameters:
	///   - nickname: The nickname as the theme formats it for the header.
	///   - spokenNickname: The nickname as a screen reader says it.
	func appendSender(
		_ profile: TranscriptSenderProfile,
		nickname: String,
		spokenNickname: String,
		nameAttributes: [NSAttributedString.Key: Any],
		separatorAttributes: [NSAttributedString.Key: Any],
		metadata: [NSAttributedString.Key: Any],
		to result: NSMutableAttributedString
	) {
		var padding = separatorAttributes
		padding[.transcriptPadding] = true

		if let avatar = profile.avatar {
			let attachment = NSTextAttachment()
			attachment.image = Self.circular(avatar, size: Self.senderAvatarSize)
			attachment.bounds = NSRect(x: 0, y: -3, width: Self.senderAvatarSize, height: Self.senderAvatarSize)
			let picture = NSMutableAttributedString(attachment: attachment)
			picture.addAttributes(padding, range: NSRange(location: 0, length: picture.length))
			result.append(picture)
			result.append(NSAttributedString(string: " ", attributes: padding))
		}

		let senderStart = result.length

		if let displayName = profile.displayName {
			var displayAttributes = nameAttributes
			displayAttributes[.transcriptPadding] = true
			TranscriptIsolate.appendIsolated(
				NSAttributedString(string: displayName, attributes: displayAttributes),
				to: result,
				isolateAttributes: separatorAttributes
			)
			result.append(NSAttributedString(string: "\u{2009}", attributes: padding))
		}

		var nicknameAttributes = nameAttributes
		if profile.displayName != nil {
			nicknameAttributes[.font] = metadata[.font] ?? nameAttributes[.font]
			nicknameAttributes[.foregroundColor] = metadata[.foregroundColor] ?? nameAttributes[.foregroundColor]
		}
		TranscriptIsolate.appendIsolated(
			NSAttributedString(string: nickname, attributes: nicknameAttributes),
			to: result,
			isolateAttributes: separatorAttributes
		)

		if let displayName = profile.displayName, result.length > senderStart {
			result.addAttribute(
				.accessibilityCustomText,
				value: [String(localized: .Transcript.senderWithDisplayName(displayName, spokenNickname))],
				range: (result.string as NSString).rangeOfComposedCharacterSequence(at: senderStart)
			)
		}
	}

	/** Redraws the held rows sent by any of `nicknames`, which are casefolded
	 by `fold`. A profile changing touches those rows and nothing else. */
	func restyleSenders(_ nicknames: Set<String>, fold: (String) -> String) {
		guard nicknames.isEmpty == false else { return }

		let indices = document.indices.filter { index in
			guard let nickname = document[index].nickname, nickname.isEmpty == false else { return false }
			return nicknames.contains(fold(nickname))
		}

		guard indices.isEmpty == false else { return }

		performEditingBatch {
			for index in indices {
				refresh(at: index)
			}
		}
	}

	/// `image` drawn into a circle `size` points across.
	static func circular(_ image: NSImage, size: CGFloat) -> NSImage {
		NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
			NSBezierPath(ovalIn: rect).addClip()
			image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
			return true
		}
	}
}
