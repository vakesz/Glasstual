// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("channel-context client tag")
struct ChannelContextTagTests {
	@Test("Both spellings are read", arguments: ["+draft/channel-context", "+channel-context"])
	func bothSpellingsAreRead(_ name: String) {
		#expect(ChannelContextTag.channelName(in: [name: "#chan"]) == "#chan")
	}

	@Test("Agreeing spellings are read, disagreeing or empty ones are not")
	func conflictsAndEmptyValues() {
		#expect(ChannelContextTag.channelName(in: ["+draft/channel-context": "#a", "+channel-context": "#a"]) == "#a")
		#expect(ChannelContextTag.channelName(in: ["+draft/channel-context": "#a", "+channel-context": "#b"]) == nil)
		#expect(ChannelContextTag.channelName(in: ["+draft/channel-context": ""]) == nil)
		#expect(ChannelContextTag.channelName(in: nil) == nil)
		#expect(ChannelContextTag.outboundName == "+draft/channel-context")
	}

	@Test("A line labels itself by where it is drawn")
	func privateContextLabels() {
		let inChannel = ChatLinePrivateContext(
			channelContext: "#Chan", privatePeer: nil, conversationName: "#chan", caseMapping: .rfc1459
		)
		let mine = ChatLinePrivateContext(
			channelContext: "#chan", privatePeer: "bot", conversationName: "#chan", caseMapping: .rfc1459
		)
		let inQuery = ChatLinePrivateContext(
			channelContext: "#chan", privatePeer: nil, conversationName: "bot", caseMapping: .rfc1459
		)

		#expect(inChannel == .privatelyInChannel(peer: nil))
		#expect(inChannel?.sender("bot") == ChatLineFormat.privateSender("bot"))
		#expect(mine?.sender("me") == ChatLineFormat.privateSender("me", to: "bot"))
		#expect(inQuery == .channel("#chan"))
		#expect(inQuery?.sender("bot") == ChatLineFormat.channelContextSender("bot", channel: "#chan"))
		#expect(ChatLinePrivateContext(channelContext: nil, privatePeer: nil, conversationName: "#chan", caseMapping: .rfc1459) == nil)
	}
}
