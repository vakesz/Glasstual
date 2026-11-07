// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

/// `findConversation(_:)` answers from a casefolded index and only scans when the
/// index may disagree with the list. Every answer must equal the scan's.
@MainActor
@Suite("Conversation lookup index")
struct ServerSessionConversationLookupTests {
	private func scan(_ session: ServerSession, _ name: String) -> Conversation? {
		session.findConversation(name, in: session.conversationList)
	}

	private func expectAgreement(_ session: ServerSession, _ names: [String]) {
		for name in names {
			#expect(session.findConversation(name) === scan(session, name), "lookup of \(name)")
		}
	}

	@Test("Lookups match a scan after creation, removal and a direct conversation rename")
	func matchesScanAcrossListChanges() throws {
		let session = TestServerSession()
		let channel = try #require(session.findConversationOrCreate("#Swift"))
		let query = try #require(session.findConversationOrCreate("alice", isDirect: true))
		let names = ["#swift", "#SWIFT", "alice", "ALICE", "bob", "#missing"]

		expectAgreement(session, names)
		#expect(session.findConversation("#swift") === channel)

		query.name = "bob"
		expectAgreement(session, names)
		#expect(session.findConversation("alice") == nil)
		#expect(session.findConversation("bob") === query)

		session.remove(channel)
		expectAgreement(session, names)
		#expect(session.findConversation("#swift") == nil)
	}

	@Test("A channel renamed by the server is found under its new name only")
	func channelRename() throws {
		let session = TestServerSession()
		let channel = try #require(session.findConversationOrCreate("#old"))

		channel.applyChannelRename(to: "#new")

		#expect(session.findConversation("#new") === channel)
		#expect(session.findConversation("#old") == nil)
		expectAgreement(session, ["#old", "#new"])
	}

	@Test("A CASEMAPPING change re-folds the index without a list change")
	func caseMappingChange() throws {
		let session = TestServerSession()
		session.supportInfo.processConfigurationData("CASEMAPPING=rfc1459")
		let channel = try #require(session.findConversationOrCreate("#a[b"))
		#expect(session.findConversation("#A{B") === channel)

		session.supportInfo.processConfigurationData("CASEMAPPING=ascii")

		#expect(session.findConversation("#A{B") == nil)
		#expect(session.findConversation("#A[B") === channel)
		expectAgreement(session, ["#A{B", "#A[B", "#a[b"])
	}
}
