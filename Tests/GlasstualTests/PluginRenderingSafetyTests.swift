/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Synchronization
import Testing

/// The message renderer is the one plugin callback the host makes off the main
/// actor, and the one edit a plugin makes to a message that goes back onto the
/// wire. Both are checked here.
@Suite("Plugin rendering safety")
@MainActor
struct PluginRenderingSafetyTests {
	private func makeHost(defaults: UserDefaults) -> PluginHostContext {
		PluginHostContext(
			defaults: defaults,
			clients: { [] },
			selectedChannel: { nil },
			metrics: {
				PluginApplicationMetrics(
					messagesSent: 0,
					messagesReceived: 0,
					bandwidthIn: 0,
					bandwidthOut: 0,
					lastMessageReceived: 0,
					visibleLineCount: 0,
					usesDarkSidebar: false
				)
			},
			applicationSnapshot: { nil },
			themeSnapshot: { nil },
			observeConnectionState: { handler in
				handler(false)
				return PluginObservation(cancellation: {})
			},
			removesFormatting: { false }
		)
	}

	private func loadSmileyConverter(defaults: UserDefaults) throws -> PluginItem {
		let bundleURL = PathInfo.bundledExtensionsURL
			.appendingPathComponent("Smiley Converter.bundle", isDirectory: true)
		let bundle = try #require(Bundle(url: bundleURL))
		defaults.set(true, forKey: FirstPartyPluginPreferences.smileyServiceEnabled.name)
		defaults.set(true, forKey: FirstPartyPluginPreferences.smileyExtraEmoticons.name)

		return try #require(PluginItem.load(bundle, host: makeHost(defaults: defaults)))
	}

	/** A renderer read a moment before the plugins unloaded used to be called
	 after `pluginWillUnload()` had run. An unload retires the publish the
	 renderers belong to before it tears a single plugin down, and a handle
	 whose publish has been retired answers nothing. */
	@Test("Unloading retires the renderers before any plugin is torn down")
	func unloadingRetiresTheRenderers() throws {
		let suiteName = "PluginRenderingSafetyTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let manager = PluginManager()
		#expect(manager.messageRendererCount == 0)
		#expect(manager.renderingMessage(":)", kind: .privateMessage) == ":)")

		let plugin = try loadSmileyConverter(defaults: defaults)
		manager.publishMessageRenderers(for: [plugin])

		let published = manager.messageRendererGeneration
		#expect(manager.messageRendererCount == 1)
		#expect(manager.renderingMessage(":)", kind: .privateMessage) == "\u{1F60A}")

		manager.unloadPlugins()
		plugin.unloadBundle()

		#expect(manager.messageRendererGeneration != published)
		#expect(manager.messageRendererCount == 0)
		#expect(manager.renderingMessage(":)", kind: .privateMessage) == ":)")
	}

	/** A renderer used to be called with the lock that retires the renderers
	 held, which put a plugin's code between the main actor and a lock the main
	 actor takes: a renderer that asked the manager anything — for its own
	 preferences pane, for how many renderers there are — took a `Mutex` that
	 does not recurse, from the thread already holding it. */
	@Test("A renderer that reaches back into the manager is answered")
	func aReentrantRendererIsAnswered() {
		let manager = PluginManager()
		let observed = Mutex<[Int]>([])
		/* One level down is the question; a renderer that re-entered on every
		 call would recurse until the stack ran out, which is the plugin's bug
		 rather than the manager's. */
		let hasReentered = Mutex(false)

		manager.publishMessageRenderers([{ event in
			observed.withLock { $0.append(manager.messageRendererCount) }
			let isOuterCall = hasReentered.withLock { entered in
				defer { entered = true }
				return entered == false
			}
			guard isOuterCall else { return "\(event.message)-again" }
			let inner = manager.renderingMessage("inner", kind: .privateMessage)
			return "\(event.message)-\(inner)"
		}])

		#expect(manager.renderingMessage("outer", kind: .privateMessage) == "outer-inner-again")
		#expect(observed.withLock(\.self) == [1, 1])
	}

	/** What an unload does to a render that is already running: retiring the
	 publish under the lock is what a call in flight sees, so the renderers after
	 the one that retired it are not reached. `unloadPlugins()` retires the same
	 way, then tears the plugins down on the main actor, which a render never
	 holds. */
	@Test("A render stops at the renderer that retired it")
	func aRetiredPublishStopsTheRender() {
		let manager = PluginManager()
		let secondWasCalled = Mutex(false)

		manager.publishMessageRenderers([
			{ event in
				manager.publishMessageRenderers([])
				return "\(event.message)-first"
			},
			{ event in
				secondWasCalled.withLock { $0 = true }
				return "\(event.message)-second"
			},
		])

		#expect(manager.renderingMessage("line", kind: .privateMessage) == "line-first")
		#expect(secondWasCalled.withLock(\.self) == false)
		#expect(manager.messageRendererCount == 0)
	}

	/// A kind the renderer does not rewrite is handed back untouched, and an
	/// empty answer never replaces the message.
	@Test("A renderer that declines leaves the message as it was")
	func decliningRendererLeavesTheMessage() throws {
		let suiteName = "PluginRenderingSafetyTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let manager = PluginManager()
		let plugin = try loadSmileyConverter(defaults: defaults)
		defer { plugin.unloadBundle() }
		manager.publishMessageRenderers(for: [plugin])

		#expect(manager.renderingMessage(":)", kind: .notice) == ":)")
	}

	/// The smiley scan asked the whole message for each of the table's
	/// nine-hundred-odd entries and then checked that what it found stood
	/// alone. Looking each space-delimited token up decides the same thing.
	@Test("Smiley conversion still replaces exactly the tokens that stand alone")
	func smileyConversionKeepsItsBoundaries() throws {
		let suiteName = "PluginRenderingSafetyTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let plugin = try loadSmileyConverter(defaults: defaults)
		defer { plugin.unloadBundle() }
		let renderer = try #require(plugin.primaryClass as? any PluginMessageRendering)

		func render(_ message: String) -> String? {
			renderer.willRenderMessage(PluginRenderEvent(message: message, kind: .privateMessage))
		}

		#expect(render(":)") == "\u{1F60A}")
		#expect(render("hello :) there") == "hello \u{1F60A} there")
		/* Not a token of its own: the boundary rule has always been a space on
		 both sides, and a run of spaces survives the round trip. */
		#expect(render("hello:)there") == "hello:)there")
		#expect(render("a  :)  b") == "a  \u{1F60A}  b")
		#expect(render(" :) ") == " \u{1F60A} ")
		#expect(render("") == "")
		/* Case is ignored, as it was when every scan was case-insensitive. */
		#expect(render(":+1:") == "\u{1F44D}")
		#expect(render(":D") == "\u{1F603}")
		#expect(render(":d") == "\u{1F603}")
		#expect(render("XD") == "\u{1F603}")
		#expect(render("xd") == "\u{1F603}")
		/* A link is left alone: the whole token has to be a smiley, and an
		 address that ends in one is not. */
		#expect(render("see https://example.test/:+1:") == "see https://example.test/:+1:")
		#expect(render("www.example.test/:+1:") == "www.example.test/:+1:")
	}

	/// A plugin's returned command and parameters used to be copied onto the
	/// message unread, so a space in the command or a CR anywhere in it wrote a
	/// second line onto the wire.
	@Test(
		"A plugin edit that would split the line is dropped",
		arguments: [
			(command: "", parameters: ["#room"]),
			(command: "PRIVMSG #room", parameters: ["hello"]),
			(command: "PRIV\r\nMSG", parameters: ["hello"]),
			(command: "PRIVMSG\n", parameters: ["hello"]),
			(command: "PRIVMSG\u{0}", parameters: ["hello"]),
			(command: "PRIVMSG", parameters: ["#room", "hello\r\nQUIT"]),
			(command: "PRIVMSG", parameters: ["#room", "hello\n"]),
		]
	)
	func invalidPluginEditsAreDropped(_ edit: (command: String, parameters: [String])) throws {
		let message = try #require(Message(line: "PRIVMSG #room :hello"))
		let edited = PluginServerMessage(
			sender: PluginSender(
				nickname: "alice",
				username: "user",
				address: "example.test",
				hostmask: "alice!user@example.test",
				isServer: false
			),
			command: edit.command,
			parameters: edit.parameters,
			isPrintOnlyMessage: true
		)

		let result = PluginHostAdapter.applying(edited, to: message)

		#expect(result === message)
		#expect(result.command == "PRIVMSG")
		#expect(result.params == ["#room", "hello"])
		#expect(result.isPrintOnlyMessage == false)
	}

	/** The sender is written as one token in front of the command, so a space in
	 any part of it splits the prefix and a CR or an LF ends the line. It used to
	 be copied onto the message unread while the command and the parameters
	 beside it were checked — and the sender is the field a plugin is most likely
	 to assemble out of what a peer sent. */
	@Test(
		"A plugin edit whose sender would split the prefix is dropped",
		arguments: [
			PluginSender(
				nickname: "alice bob", username: "user",
				address: "example.test", hostmask: "alice!user@example.test", isServer: false
			),
			PluginSender(
				nickname: "alice", username: "user name",
				address: "example.test", hostmask: "alice!user@example.test", isServer: false
			),
			PluginSender(
				nickname: "alice", username: "user",
				address: "example.test\r\nQUIT", hostmask: "alice!user@example.test", isServer: false
			),
			PluginSender(
				nickname: "alice", username: "user",
				address: "example.test", hostmask: "alice!user@example.test QUIT", isServer: false
			),
			PluginSender(
				nickname: "alice", username: "user",
				address: "example.test", hostmask: "alice\u{0}", isServer: false
			),
		]
	)
	func invalidPluginSendersAreDropped(_ sender: PluginSender) throws {
		let message = try #require(Message(line: ":carol!user@example.test PRIVMSG #room :hello"))
		let edited = PluginServerMessage(
			sender: sender,
			command: "PRIVMSG",
			parameters: ["#room", "hello"],
			isPrintOnlyMessage: false
		)

		let result = PluginHostAdapter.applying(edited, to: message)

		#expect(result === message)
		#expect(result.sender.nickname == "carol")
	}

	/// A message with no prefix at all is the common case for a server line, and
	/// an absent part is not a split one.
	@Test("A plugin edit with an empty sender is applied")
	func emptyPluginSendersAreApplied() throws {
		let message = try #require(Message(line: "PING :token"))
		let edited = PluginServerMessage(
			sender: PluginSender(nickname: "", username: nil, address: nil, hostmask: "", isServer: true),
			command: "PONG",
			parameters: ["token"],
			isPrintOnlyMessage: false
		)

		let result = PluginHostAdapter.applying(edited, to: message)

		#expect(result !== message)
		#expect(result.command == "PONG")
	}

	/// The edits that can go on the wire still apply, spaces in a trailing
	/// parameter included.
	@Test("A plugin edit that fits on one line still applies")
	func validPluginEditsApply() throws {
		let message = try #require(Message(line: "PRIVMSG #room :hello"))
		let edited = PluginServerMessage(
			sender: PluginSender(
				nickname: "alice",
				username: "user",
				address: "example.test",
				hostmask: "alice!user@example.test",
				isServer: false
			),
			command: "JOIN",
			parameters: ["#room", "a trailing parameter with spaces"],
			isPrintOnlyMessage: true
		)

		let result = PluginHostAdapter.applying(edited, to: message)

		#expect(result !== message)
		#expect(result.command == "JOIN")
		#expect(result.params == ["#room", "a trailing parameter with spaces"])
		#expect(result.isPrintOnlyMessage)
		#expect(result.sender.nickname == "alice")
	}
}
