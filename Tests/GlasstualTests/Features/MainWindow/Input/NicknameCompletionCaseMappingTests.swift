// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
private final class CaseMappingCompletionWindow: NicknameCompletionWindow {
	var inputTextField: InputField!
	var selectedSession: ServerSession?
	var selectedConversation: Conversation?
}

/// A nickname is completed under the casemapping the server advertised, because
/// that is the rule the server applies when it decides two names are the same.
@MainActor
@Suite("Nickname completion casemapping", .serialized)
struct NicknameCompletionCaseMappingTests {
	/// Types `typed` into a field of a channel that holds `nicknames`, completes
	/// once and answers what the field then holds.
	private func completed(
		_ typed: String,
		among nicknames: [String],
		casemapping: String?,
		kind: String = "#chat"
	) -> String {
		let session = TestServerSession()
		if let casemapping {
			session.apply(session.supportInfo.processConfigurationData("CASEMAPPING=\(casemapping)"))
		}
		let channel = Conversation(config: ConversationConfig(name: kind))
		channel.associatedSession = session
		channel.activate()
		for nickname in nicknames {
			channel.addUser(session.findUserOrCreate(nickname))
		}
		let host = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
			styleMask: .borderless, backing: .buffered, defer: false
		)
		let textField = InputField(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
		host.contentView?.addSubview(textField)
		let window = CaseMappingCompletionWindow()
		window.selectedSession = session
		window.selectedConversation = channel
		window.inputTextField = textField
		textField.stringValue = typed
		textField.setSelectedRange(NSRange(location: (typed as NSString).length, length: 0))
		NicknameCompletion(window: window).completeNickname(true)
		return textField.string
	}

	@Test("Under rfc1459 a bracket in the pattern completes the brace it is the same letter as")
	func rfc1459FoldsBrackets() {
		#expect(completed("[a", among: ["{abc"], casemapping: "rfc1459").hasPrefix("{abc"))
	}

	@Test("A session that advertised no casemapping uses rfc1459")
	func defaultsToRFC1459() {
		#expect(completed("[a", among: ["{abc"], casemapping: nil).hasPrefix("{abc"))
	}

	@Test("Under ascii the same pattern completes nothing")
	func asciiDoesNotFoldBrackets() {
		#expect(completed("[a", among: ["{abc"], casemapping: "ascii") == "[a")
	}

	@Test("Under rfc7613 a non-ASCII nickname completes from its lowercase form, and under ascii it does not")
	func unicodeFollowsTheMapping() {
		#expect(completed("ál", among: ["Álice"], casemapping: "rfc7613").hasPrefix("Álice"))
		#expect(completed("ál", among: ["Álice"], casemapping: "ascii") == "ál")
	}

	@Test("Case still does not matter for ASCII letters")
	func asciiLettersFold() {
		#expect(completed("AL", among: ["alice"], casemapping: "rfc1459").hasPrefix("alice"))
	}
}
