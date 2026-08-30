@testable import Glasstual
import Testing

/// `Message` kept reference semantics — it points back at its `MessageBatch` —
/// so editing one means taking a `duplicate()` first.
@MainActor
struct IRCMessageDuplicateTests {
	@Test("A duplicate carries every field the mutable subclass used to expose")
	func duplicateCarriesEveryField() throws {
		let line = "@msgid=abc;account=bob;batch=b1 :bob!b@h PRIVMSG #c :hi there"
		let message = try #require(Message(line: line))
		message.markAsHistoric()

		let copy = message.duplicate()

		#expect(copy !== message)
		#expect(copy.sender == message.sender)
		#expect(copy.command == message.command)
		#expect(copy.commandNumeric == message.commandNumeric)
		#expect(copy.params == message.params)
		#expect(copy.receivedAt == message.receivedAt)
		#expect(copy.isHistoric)
		#expect(copy.isEventOnlyMessage == message.isEventOnlyMessage)
		#expect(copy.isPrintOnlyMessage == message.isPrintOnlyMessage)
		#expect(copy.batchToken == message.batchToken)
		#expect(copy.messageTags == message.messageTags)
		#expect(copy.messageIdentifier == "abc")
		#expect(copy.senderAccount == "bob")
		#expect(copy.parentBatchMessage === message.parentBatchMessage)
	}

	@Test("Editing a duplicate leaves the original alone")
	func duplicatesAreIndependent() throws {
		let message = try #require(Message(line: ":n!u@h PRIVMSG #c :hi"))

		let copy = message.duplicate()
		copy.command = "NOTICE"
		copy.params = ["#c", "rewritten"]
		copy.sender = Prefix(nickname: "other", hostmask: "other", isServer: true)

		#expect(message.command == "PRIVMSG")
		#expect(message.params == ["#c", "hi"])
		#expect(message.sender.nickname == "n")
		#expect(copy.sender.isServer)
	}

	@Test("Parameter accessors read past the end without trapping")
	func parameterAccessorsAreBounded() throws {
		let message = try #require(Message(line: "PING :token"))

		#expect(message.param(at: 0) == "token")
		#expect(message.param(at: 9) == "")
		#expect(message.sequence(9) == "")
		#expect(message.paramsCount == 1)
	}
}
