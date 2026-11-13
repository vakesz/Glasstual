// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Member list display names", .timeLimit(.minutes(1)))
struct MemberListDisplayNameTests {
	private func presentation(on session: TestServerSession) throws -> ServerProfilePresentation {
		let channel = try #require(session.findConversation("#c"))
		return ServerProfilePresentation(
			session: session,
			conversation: channel,
			nicknames: channel.memberInfo?.memberList.map(\.user.nickname) ?? [],
			inlineMediaDefault: false
		)
	}

	@Test("A row shows the display name with the nickname, and speaks both")
	func rowShowsBoth() throws {
		let session = try makeMetadataSession()
		try session.receive(":irc.example.net METADATA peer display-name * :Peer Display")
		let peerUser = try #require(session.findUser("peer"))
		let peer = try #require(session.findConversation("#c")?.memberInfo?.findMember(withUserID: peerUser.id))

		let profile = try MemberRowProfile(peer.user, presentation: presentation(on: session))
		let label = MemberListTableRow.member(peer).accessibilityDescription(
			style: MemberListPresentationStyle.current(), displayName: profile.displayName
		)

		#expect(profile.displayName == "Peer Display")
		#expect(label.hasPrefix(String(localized: .MemberList.userWithDisplayName("Peer Display", "peer"))))
	}

	@Test("A name that collides with a member, the local user or a service is hidden", arguments: [
		"peer", "ADA", "NickServ", "spoof",
	])
	func collisionHides(_ name: String) throws {
		let session = try makeMetadataSession()
		try session.receive(":irc.example.net METADATA spoof display-name * :\(name)")
		let spoof = try #require(session.findUser("spoof"))

		#expect(try MemberRowProfile(spoof, presentation: presentation(on: session)).displayName == nil)
	}

	/** Folding every nickname is the cost of a display name check, and the
	 member list builds a presentation each time its members change: during a
	 join burst that fold over the whole channel ran on every change. */
	@Test("The collision set is folded only once a member with a display name is drawn")
	func collisionsFoldOnlyForDisplayNames() throws {
		let session = try makeMetadataSession()
		let presentation = try presentation(on: session)
		let peer = try #require(session.findUser("peer"))

		#expect(presentation.displayName(for: peer) == nil)
		#expect(presentation.hasFoldedCollisions == false)

		try session.receive(":irc.example.net METADATA peer display-name * :Peer Display")
		let named = try #require(session.findUser("peer"))
		#expect(presentation.displayName(for: named) == "Peer Display")
		#expect(presentation.hasFoldedCollisions)
	}

	@Test("Nothing is shown with Show Server Profiles off")
	func settingOff() throws {
		let session = try makeMetadataSession()
		try session.receive(":irc.example.net METADATA peer display-name * :Peer Display")
		session.environment.settings.showsServerProfiles = false
		let peer = try #require(session.findUser("peer"))

		#expect(try MemberRowProfile(peer, presentation: presentation(on: session)).displayName == nil)
	}

	@Test("No picture is fetched while inline images are off")
	func noFetchWithoutInlineMedia() throws {
		let session = try makeMetadataSession()
		try session.receive(":irc.example.net METADATA peer avatar * :https://example.org/{size}.png")
		let peer = try #require(session.findUser("peer"))
		let presentation = try presentation(on: session)

		#expect(presentation.fetchesAvatars == false)
		#expect(presentation.avatar(for: peer.profile, pixelSize: 64) == nil)
		#expect(try RemoteImageStore.avatars.isFetching(
			#require(URL(string: "https://example.org/64.png")), route: .system
		) == false)
	}
}
