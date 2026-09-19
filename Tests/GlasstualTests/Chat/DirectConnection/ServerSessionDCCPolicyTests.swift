// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("DCC request policy")
struct ServerSessionDCCPolicyTests {
	@Test("A quoted SEND keeps its spaces and the token loses its T prefix")
	func parsesQuotedSendAndNormalizesToken() {
		let request = DCCFileTransferRequestParser.parse("SEND \"hello world.txt\" 3232235777 0 42 T123")

		#expect(
			request
				== .send(filename: "hello world.txt", address: "192.168.1.1", port: 0, filesize: 42, token: "123")
		)
	}

	@Test("A transfer outside the legal port or size range is refused")
	func rejectsInvalidFileTransferRanges() {
		#expect(DCCFileTransferRequestParser.parse("SEND file 3232235777 0 42") == nil)
		#expect(DCCFileTransferRequestParser.parse("SEND file 3232235777 65536 42") == nil)
		#expect(
			DCCFileTransferRequestParser.parse("SEND file 3232235777 5000 0")
				== .send(filename: "file", address: "192.168.1.1", port: 5000, filesize: 0, token: nil)
		)
		#expect(DCCFileTransferRequestParser.parse("RESUME file 5000 12 token") == nil)
	}

	@Test("Outgoing RESUME and SEND arguments quote only the filenames that need it")
	func formatsResumeAndSendArguments() {
		#expect(
			DCCFileTransferRequestParser.transferArguments(
				filename: "hello world.txt", port: 5000, position: 12, token: "7"
			) == "\"hello world.txt\" 5000 12 7"
		)
		#expect(
			DCCFileTransferRequestParser.sendArguments(
				filename: "file.txt", address: "42", port: 5000, filesize: 99, token: nil
			) == "file.txt 42 5000 99"
		)
	}

	@Test("Both an active and a passive chat offer are understood")
	func parsesActiveAndPassiveChatOffers() {
		#expect(
			DirectChatPolicy.parseOffer("CHAT chat 1568397154 5000")
				== DirectChatOffer(address: "93.123.215.98", port: 5000, token: nil)
		)
		#expect(
			DirectChatPolicy.parseOffer("CHAT chat 0 0 T99")
				== DirectChatOffer(address: "0.0.0.0", port: 0, token: "99")
		)
		#expect(DirectChatPolicy.parseOffer("CHAT chat invalid 5000") == nil)
		#expect(DirectChatPolicy.parseOffer("CHAT chat 3232235777 0") == nil)
	}

	/** An active chat offer decides which host the session dials, exactly as a
	 DCC SEND offer does. The parser understands a private address — it is a
	 well-formed offer — but the session refuses to act on it. */
	@Test("A chat offer naming an address the session will not dial is refused")
	func refusesChatOffersForNonRoutableAddresses() throws {
		let privateOffer = try #require(DirectChatPolicy.parseOffer("CHAT chat 3232235777 5000"))

		#expect(privateOffer.address == "192.168.1.1")
		#expect(DirectChatPolicy.isDialable(privateOffer) == false)

		let loopbackOffer = try #require(DirectChatPolicy.parseOffer("CHAT chat 2130706433 5000"))

		#expect(loopbackOffer.address == "127.0.0.1")
		#expect(DirectChatPolicy.isDialable(loopbackOffer) == false)

		let routableOffer = try #require(DirectChatPolicy.parseOffer("CHAT chat 1568397154 5000"))

		#expect(DirectChatPolicy.isDialable(routableOffer))
	}

	/// A passive offer names no address at all: the peer connects to us, so
	/// there is nothing to dial and nothing to refuse.
	@Test("A passive chat offer is not refused for the placeholder address it carries")
	func passiveChatOffersAreNotRefusedForTheirPlaceholderAddress() throws {
		let offer = try #require(DirectChatPolicy.parseOffer("CHAT chat 0 0 T99"))

		#expect(offer.isPassive)
		#expect(DirectChatPolicy.isDialable(offer))
	}

	@Test("A direct chat is named and offered in the legacy wire format")
	func directChatWireNames() {
		#expect(DirectChatPolicy.conversationName(for: "alice") == "=alice")
		#expect(DirectChatPolicy.listeningArguments(address: "42", port: 5000, token: "9") == "chat 42 5000 9")
	}
}
