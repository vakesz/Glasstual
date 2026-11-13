// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/** The profiles senders set on the server, for the headers this transcript
 draws.

 A header asks at draw time on the main actor, so a profile or a picture that
 changes later redraws the rows already held without rendering them again. */
extension TranscriptController {
	/** The profile drawn in `nickname`'s header, if profiles are shown and they
	 set one. The presentation compares display names against every member, so
	 it is built only for a sender who has something to show: a line from
	 anyone else used to rebuild it after each change to a large member list. */
	func senderProfile(for nickname: String) -> TranscriptSenderProfile? {
		guard let session = associatedSession, session.environment.settings.showsServerProfiles,
		      let user = session.findUser(nickname), user.profile.isEmpty == false
		else { return nil }

		let presentation = currentSenderPresentation(on: session)

		return TranscriptSenderProfile(
			displayName: presentation.displayName(for: user),
			color: presentation.color(for: user),
			avatar: presentation.avatar(for: user.profile, pixelSize: ServerProfilePresentation.transcriptPixelSize)
		)
	}

	func observeSenderProfiles() {
		profileSubscriptions.observe(SessionProfilesDidChange.self) { [weak self] message in
			guard let self, message.subject === associatedSession else { return }
			senderPresentation = nil
			if message.isReset {
				backingView?.applyTheme()
			} else {
				restyleSenders(message.nicknames)
			}
		}
		profileSubscriptions.observe(RemoteImageStoreDidChange.self, of: RemoteImageStore.avatars) { [weak self] _ in
			self?.restyleSendersWithPictures()
		}
	}

	private func currentSenderPresentation(on session: ServerSession) -> ServerProfilePresentation {
		/* Everything the presentation was read from is in the key, so a setting
		 or an override switched off is never answered from the cache. */
		let key = SenderPresentationKey(
			memberRevision: associatedConversation?.memberInfo?.renderRevision ?? 0,
			showsInlineMedia: settings.current.showsInlineMedia,
			conversationConfig: associatedConversation?.config,
			showsProfiles: session.environment.settings.showsServerProfiles,
			userCount: session.userIndex.values.count
		)

		if let cached = senderPresentation, cached.key == key {
			return cached.value
		}

		let value = ServerProfilePresentation(
			session: session,
			conversation: associatedConversation,
			nicknames: ServerProfilePresentation.comparedNicknames(in: associatedConversation, on: session),
			inlineMediaDefault: settings.current.showsInlineMedia
		)
		senderPresentation = (key, value)

		return value
	}

	private func restyleSenders(_ nicknames: Set<String>) {
		guard let session = associatedSession else { return }
		backingView?.restyleSenders(nicknames) { [weak session] in session?.casefoldNickname($0) ?? $0 }
	}

	/// A picture arrived: redraw the senders that have one.
	private func restyleSendersWithPictures() {
		guard let session = associatedSession, let members = associatedConversation?.memberInfo?.memberList else { return }

		let nicknames = Set(members.lazy.filter { $0.user.profile.avatar != nil }.map { session.casefoldNickname($0.user.nickname) })
		restyleSenders(nicknames)
	}
}

/// What a cached sender presentation was read from.
struct SenderPresentationKey: Equatable {
	let memberRevision: UInt64
	let showsInlineMedia: Bool
	let conversationConfig: ConversationConfig?
	let showsProfiles: Bool
	let userCount: Int
}
