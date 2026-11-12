// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** How the profiles people set on a server are drawn in one conversation.

 Taken once per redraw by the member list and the transcript, so every row
 answers from the same members, settings and route. Profile pictures are
 fetched on demand for the rows being drawn, only where images are shown for
 the conversation and the session's route fetches avatars on its own; the
 initial on the profile colour stands in otherwise. */
@MainActor
struct ServerProfilePresentation {
	/// Pixel sizes a picture is asked for, for the 32 and 16 point avatars at 2×.
	static let memberListPixelSize = 64
	static let transcriptPixelSize = 32

	let showsProfiles: Bool
	let fetchesAvatars: Bool
	private let route: InlineImageRoute
	private let owner: String
	private let collisions: CollisionForms
	private let casefold: (String) -> String
	private let images: RemoteImageStore

	/// Nothing shown: no session, or profiles switched off.
	init() {
		showsProfiles = false
		fetchesAvatars = false
		route = .unavailable
		owner = ""
		collisions = CollisionForms(nicknames: [], localNickname: "", casefold: { $0 })
		casefold = { $0 }
		images = .avatars
	}

	/// - Parameters:
	///   - inlineMediaDefault: The app-wide inline image setting.
	///   - nicknames: Who else the conversation names: its members.
	init(
		session: ServerSession,
		conversation: Conversation?,
		nicknames: some Sequence<String>,
		inlineMediaDefault: Bool,
		images: RemoteImageStore = .avatars
	) {
		let showsProfiles = session.environment.settings.showsServerProfiles
		let showsMedia = conversation?.config.showsInlineMedia(settingsDefault: inlineMediaDefault) ?? inlineMediaDefault
		let fold: (String) -> String = { [weak session] in session?.casefoldNickname($0) ?? $0.lowercased() }

		self.showsProfiles = showsProfiles
		fetchesAvatars = showsProfiles && showsMedia
		route = InlineImageRoute(session: session)
		owner = session.uniqueIdentifier
		casefold = fold
		collisions = CollisionForms(nicknames: Array(nicknames), localNickname: session.userNickname, casefold: fold)
		self.images = images
	}

	/** The nicknames a display name in `conversation` must not pass for.

	 A channel's members are who its rows and lines name. A conversation with
	 one person, or none, is compared against everyone the session knows, so a
	 name in a query cannot pass for someone from a shared channel. */
	static func comparedNicknames(in conversation: Conversation?, on session: ServerSession) -> [String] {
		comparedNicknames(
			channelMembers: conversation?.isChannel == true ? conversation?.memberInfo?.memberList : nil,
			on: session
		)
	}

	/// The same, from members the caller already holds: a list that is being
	/// replaced must not be read back through its conversation.
	static func comparedNicknames(channelMembers: [Member]?, on session: ServerSession) -> [String] {
		if let channelMembers {
			return channelMembers.map(\.user.nickname)
		}

		return session.userIndex.values.map(\.nickname)
	}

	/** The display name drawn beside `user`'s nickname, if any.

	 The person's own nickname is in the collision set too. That needs no
	 exception here: a display name equal to it is refused as redundant before
	 the set is consulted, and any other name is not their nickname. */
	func displayName(for user: User) -> String? {
		guard showsProfiles, user.profile.displayName != nil else { return nil }

		return ProfileNamePresentation.displayName(
			for: user.profile, nickname: user.nickname, collisions: collisions.forms, casefold: casefold
		)
	}

	/// Whether the collision set has been folded. For tests.
	var hasFoldedCollisions: Bool {
		collisions.isFolded
	}

	/// The colour the person chose, when profiles are shown.
	func color(for user: User) -> ProfileColor? {
		showsProfiles ? user.profile.color : nil
	}

	/// The person's picture once it has arrived, asking for it when it may be.
	func avatar(for profile: UserProfile, pixelSize: Int) -> NSImage? {
		guard fetchesAvatars, let url = profile.avatar?.url(pixelSize: pixelSize) else { return nil }

		if let image = images.image(for: url) {
			return image
		}
		images.request(url, route: route, owner: owner)

		return nil
	}
}

/** The names a display name must not pass for, folded on first use. Only a
 member who set a display name needs them, and folding every nickname of a
 large channel each time its list changed held up the main actor through a
 join burst. A class, so the copies of one presentation share one fold. */
@MainActor
private final class CollisionForms {
	private let nicknames: [String]
	private let localNickname: String
	private let casefold: (String) -> String
	private var folded: Set<String>?

	init(nicknames: [String], localNickname: String, casefold: @escaping (String) -> String) {
		self.nicknames = nicknames
		self.localNickname = localNickname
		self.casefold = casefold
	}

	var isFolded: Bool {
		folded != nil
	}

	var forms: Set<String> {
		if let folded {
			return folded
		}
		let forms = ProfileNamePresentation.collisionForms(
			nicknames: nicknames, localNickname: localNickname, casefold: casefold
		)
		folded = forms
		return forms
	}
}
