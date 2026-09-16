/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@MainActor
private final class CompletionWindow: NicknameCompletionWindow {
	var inputTextField: MainWindowTextView!
	var selectedClient: Client?
	var selectedChannel: Channel?
}

@MainActor
@Suite("Input handling", .serialized)
struct InputHandlingTests {
	private static let channelSpecificHistoryKey = "SaveInputHistoryPerSelection"
	private static let completionSuffixKey = "Keyboard -> Tab Key Completion Suffix"

	/// The tests run against the scheme's scratch defaults suite, so whatever
	/// the key held is put back rather than left behind.
	private func withPreference(_ key: String, setTo value: Any, _ body: () throws -> Void) rethrows {
		let defaults = GlasstualUserDefaults.container
		let original = defaults.persistedObject(forKey: key)
		defer {
			if let original {
				defaults.set(original, forKey: key)
			} else {
				defaults.removeObject(forKey: key)
			}
		}

		defaults.set(value, forKey: key)

		try body()
	}

	/// The completion reads the field's window, so the host outlives the field.
	private func hostWindow() -> NSWindow {
		NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
	}

	private func makeTextField(in host: NSWindow) -> MainWindowTextView {
		let textField = MainWindowTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
		host.contentView?.addSubview(textField)

		return textField
	}

	private func makeChannel(on client: Client, nicknames: [String]) -> Channel {
		let channel = Channel(config: ChannelConfig(channelName: "#chat"))
		channel.associatedClient = client
		channel.activate()
		for nickname in nicknames {
			channel.addUser(client.findUserOrCreate(nickname))
		}
		return channel
	}

	@Test("Walking the input history skips a repeat of the entry before it")
	func inputHistoryNavigatesEntriesAndSkipsConsecutiveDuplicates() {
		withPreference(Self.channelSpecificHistoryKey, setTo: false) {
			let window = MainWindow(
				contentRect: .zero,
				styleMask: .borderless,
				backing: .buffered,
				defer: false
			)
			let history = InputHistory(window: window)

			history.add(NSAttributedString(string: "first"))
			history.add(NSAttributedString(string: "second"))
			history.add(NSAttributedString(string: "second"))

			#expect(history.up(NSAttributedString(string: ""))?.string == "second")
			#expect(history.up(NSAttributedString(string: "second"))?.string == "first")
			#expect(history.down(NSAttributedString(string: "first"))?.string == "second")
			#expect(history.down(NSAttributedString(string: "second"))?.string == "")
		}
	}

	@Test("Completing a local command keeps the command prefix and adds a space")
	func nicknameCompletionCompletesLocalCommandAndPreservesCommandPrefix() {
		let host = hostWindow()
		let textField = makeTextField(in: host)
		let window = CompletionWindow()
		window.inputTextField = textField
		textField.stringValue = "/jo"
		textField.setSelectedRange(NSRange(location: 3, length: 0))

		let completion = NicknameCompletionStatus(window: window)

		completion.completeNickname(true)
		#expect(textField.string == "/join ")
		#expect(textField.selectedRange.location == 6)
	}

	@Test("Completing a nickname draws on the channel members and the configured suffix")
	func nicknameCompletionUsesChannelMembersAndConfiguredSuffix() {
		withPreference(Self.completionSuffixKey, setTo: ": ") {
			let client = TestClient()
			let channel = makeChannel(on: client, nicknames: ["Alice"])

			let host = hostWindow()
			let textField = makeTextField(in: host)
			let window = CompletionWindow()
			window.selectedClient = client
			window.selectedChannel = channel
			window.inputTextField = textField
			textField.stringValue = "Al"
			textField.setSelectedRange(NSRange(location: 2, length: 0))

			let completion = NicknameCompletionStatus(window: window)

			completion.completeNickname(true)
			#expect(textField.string == "Alice: ")
		}
	}

	@Test("Repeated completion cycles through one coherent session in both directions")
	func nicknameCompletionCyclesThroughCandidates() {
		withPreference(Self.completionSuffixKey, setTo: ": ") {
			let client = TestClient()
			let channel = makeChannel(on: client, nicknames: ["Bob", "Alice"])

			let host = hostWindow()
			let textField = makeTextField(in: host)
			let window = CompletionWindow()
			window.selectedClient = client
			window.selectedChannel = channel
			window.inputTextField = textField
			textField.setSelectedRange(NSRange(location: 0, length: 0))

			let completion = NicknameCompletionStatus(window: window)

			completion.completeNickname(true)
			#expect(textField.string == "Alice: ")

			completion.completeNickname(true)
			#expect(textField.string == "Bob: ")

			completion.completeNickname(false)
			#expect(textField.string == "Alice: ")
		}
	}

	@Test("Production completion over a large attached member list never publishes weight decay")
	func largeMemberListCompletionDoesNotPublish() {
		let client = TestClient()
		let channel = Channel(config: ChannelConfig(channelName: "#completion"))
		channel.associatedClient = client
		channel.activate()
		let memberList = MemberList()
		memberList.assign(to: channel)
		let beforeNames = memberList.presentationRevision
		channel.withMemberPresentationUpdates {
			for index in 0 ..< 2048 {
				channel.addUser(client.findUserOrCreate(String(format: "member%04d", index)))
			}
			channel.addUser(client.findUserOrCreate("_memberTrimmed"))
		}
		#expect(memberList.presentationRevision == beforeNames + 1)
		let publicationCount = memberList.presentationRevision
		channel.recordConversation(with: "member2047", direction: .incoming)
		channel.recordConversation(with: "member2046", direction: .outgoing)
		let cache = MemberListRenderCache()
		let snapshot = cache.members(in: channel)

		let host = hostWindow()
		let textField = makeTextField(in: host)
		let window = CompletionWindow()
		window.inputTextField = textField
		window.selectedClient = client
		window.selectedChannel = channel
		let completion = NicknameCompletionStatus(window: window)
		textField.stringValue = "say @member"
		textField.setSelectedRange(NSRange(location: textField.string.utf16.count, length: 0))
		completion.completeNickname(true)
		#expect(textField.string == "say @member2047 ")
		completion.completeNickname(true)
		#expect(textField.string == "say @member2046 ")
		completion.completeNickname(false)
		#expect(textField.string == "say @member2047 ")

		completion.clear()
		textField.stringValue = "say @memberT"
		textField.setSelectedRange(NSRange(location: textField.string.utf16.count, length: 0))
		completion.completeNickname(true)
		#expect(textField.string == "say @_memberTrimmed ")
		completion.clear()
		textField.stringValue = "say @"
		textField.setSelectedRange(NSRange(location: textField.string.utf16.count, length: 0))
		completion.completeNickname(true)
		#expect(textField.string == "say @member2047 ")
		#expect(channel.findMember("member2047")?.totalWeight == 100)
		#expect(memberList.presentationRevision == publicationCount)
		#expect(cache.members(in: channel) == snapshot)
		#expect(cache.rebuildCount == 1)
	}

	/// The loading screen makes the field uneditable, which is what makes
	/// `shouldChangeText` refuse. The session must not then record a range for
	/// an edit that never happened, or the next Tab replaces from it.
	@Test("A refused completion changes neither the field nor the session")
	func nicknameCompletionLeavesNoSessionWhenTheEditIsRefused() {
		withPreference(Self.completionSuffixKey, setTo: ": ") {
			let client = TestClient()
			let channel = makeChannel(on: client, nicknames: ["Alice"])

			let host = hostWindow()
			let textField = makeTextField(in: host)
			let window = CompletionWindow()
			window.selectedClient = client
			window.selectedChannel = channel
			window.inputTextField = textField
			textField.stringValue = "Al"
			textField.setSelectedRange(NSRange(location: 2, length: 0))
			textField.isEditable = false

			let completion = NicknameCompletionStatus(window: window)

			completion.completeNickname(true)
			#expect(textField.string == "Al")
			#expect(textField.selectedRange == NSRange(location: 2, length: 0))

			completion.completeNickname(true)
			#expect(textField.string == "Al")
		}
	}
}
