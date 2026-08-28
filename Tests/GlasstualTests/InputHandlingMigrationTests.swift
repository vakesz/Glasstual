/*  *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@MainActor
private final class GLTCompletionWindow: NicknameCompletionWindow {
	var inputTextField: MainWindowTextView!
	var selectedClient: IRCClient?
	var selectedChannel: Channel?
}

@MainActor
class GLTCompletionChannel: Channel, @unchecked Sendable {
	var testMembers: [ChannelUser] = []

	override var channelMembers: [ChannelUser] {
		testMembers
	}
}

@MainActor
@Suite("Input handling", .serialized)
struct InputHandlingMigrationTests {
	private static let channelSpecificHistoryKey = "SaveInputHistoryPerSelection"
	private static let completionSuffixKey = "Keyboard -> Tab Key Completion Suffix"

	/// The tests run against the scheme's scratch defaults suite, so whatever
	/// the key held is put back rather than left behind.
	private func withPreference(_ key: String, setTo value: Any, _ body: () throws -> Void) rethrows {
		let defaults = TextualUserDefaults.shared()
		let original = defaults.persistentDomain(forName: ApplicationGroup.identifier)?[key]
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

	private func keyEvent(_ characters: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16) throws -> NSEvent {
		try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: modifiers,
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: characters,
			charactersIgnoringModifiers: characters,
			isARepeat: false,
			keyCode: keyCode
		))
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

	@Test("Walking the input history skips a repeat of the entry before it")
	func inputHistoryNavigatesEntriesAndSkipsConsecutiveDuplicates() {
		withPreference(Self.channelSpecificHistoryKey, setTo: false) {
			let window = TVCMainWindow(
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

	/** Key event handlers are registered with closures now; the selector-based
	 registration and its NSObject target requirement are gone. */
	@Test("A registered character and modifier pair reaches its closure")
	func keyEventHandlerDispatchesRegisteredKeyCode() throws {
		let handler = KeyEventHandler()
		let event = try keyEvent("a", modifiers: .command, keyCode: 42)
		var invocationCount = 0
		var lastEvent: NSEvent?

		handler.register(character: "a", modifiers: .command) { event in
			invocationCount += 1
			lastEvent = event
		}

		#expect(handler.processKeyEvent(event))
		#expect(invocationCount == 1)
		#expect(lastEvent == event)
	}

	@Test("An uppercase character falls back to its lowercase registration")
	func keyEventHandlerFallsBackToCaseInsensitiveCharacter() throws {
		let handler = KeyEventHandler()
		let event = try keyEvent("A", modifiers: [], keyCode: 42)
		var invocationCount = 0

		handler.register(character: "a") { _ in invocationCount += 1 }

		#expect(handler.processKeyEvent(event))
		#expect(invocationCount == 1)
	}

	@Test("An unregistered event is left for the responder chain")
	func keyEventHandlerReturnsNoForUnregisteredEvent() throws {
		let handler = KeyEventHandler()
		let event = try keyEvent("z", modifiers: [], keyCode: 6)
		var invocationCount = 0

		handler.register(character: "a") { _ in invocationCount += 1 }

		#expect(handler.processKeyEvent(event) == false)
		#expect(invocationCount == 0)
	}

	@Test("A shortcut registered by key code dispatches the same way")
	func keyEventHandlerDispatchesTypedShortcutAction() throws {
		let handler = KeyEventHandler()
		let event = try keyEvent("\u{1b}", modifiers: .command, keyCode: KeyCode.escape.rawValue)
		var receivedEvent: NSEvent?
		handler.register(key: .escape, modifiers: .command) { receivedEvent = $0 }

		#expect(handler.processKeyEvent(event))
		#expect(receivedEvent == event)
	}

	@Test("Completing a local command keeps the command prefix and adds a space")
	func nicknameCompletionCompletesLocalCommandAndPreservesCommandPrefix() {
		CommandIndex.populateCommandIndex()

		let host = hostWindow()
		let textField = makeTextField(in: host)
		let window = GLTCompletionWindow()
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
			let client = GLTTestClient()
			let member = GLTTestClient.testChannelUser(nickname: "Alice", on: client)
			let channel = GLTCompletionChannel(config: ChannelConfig(channelName: "#chat"))

			channel.testMembers = [member]

			let host = hostWindow()
			let textField = makeTextField(in: host)
			let window = GLTCompletionWindow()
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
}
