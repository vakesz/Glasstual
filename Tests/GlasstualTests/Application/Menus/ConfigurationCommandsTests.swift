// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

/** `/serverconfig`, `/channelconfig` and `/setcolor` with a colour: the
 editors' settings, changed through the editors' own models and refused the
 way the sheets refuse them. */
@MainActor
@Suite("Configuration commands", .serialized, .timeLimit(.minutes(1)))
struct ConfigurationCommandsTests {
	private let commands = ConfigurationCommands()

	private func session() -> TestServerSession {
		let session = TestServerSession(configDictionary: [
			"nickname": "ada", "username": "ada", "realName": "Ada", "connectionName": "Example",
		])
		var config = session.config
		config.serverList = [ServerEndpoint(serverAddress: "irc.example.test", serverPort: 6697, prefersSecuredConnection: true)]
		session.updateConfig(config)
		return session
	}

	@Test("A flag, a text and a number change the stored configuration")
	func changesSettings() {
		let session = session()

		#expect(commands.performServerConfiguration("autoreconnect on", on: session)
			== [String(localized: .IRC.configSettingChanged("autoreconnect", "on"))])
		#expect(commands.performServerConfiguration("quit-message Off to tea", on: session).count == 1)
		#expect(commands.performServerConfiguration("flood-maximum 7", on: session).count == 1)

		#expect(session.config.autoReconnect)
		#expect(session.config.normalLeavingComment == "Off to tea")
		#expect(session.config.floodControlMaximumMessages == 7)
	}

	@Test("A value the sheet refuses is refused with the sheet's own message")
	func validationParity() {
		let session = session()
		let model = ServerPropertiesModel(config: session.config)
		model.config.nickname = "1nvalid!"
		let sheetMessage = model.validationFault?.message

		let lines = commands.performServerConfiguration("nickname 1nvalid!", on: session)

		#expect(lines == [CommonValidationStrings.invalidNickname])
		#expect(sheetMessage == CommonValidationStrings.invalidNickname)
		#expect(session.config.nickname == "ada")
	}

	@Test("A value the setting cannot hold names what it takes")
	func invalidValue() {
		let lines = commands.performServerConfiguration("tls maybe", on: session())
		#expect(lines == [String(localized: .IRC.configInvalidValue("tls", "maybe", "on | off"))])
	}

	@Test("A secret is never taken from the command line")
	func secretRefused() {
		let session = session()
		let lines = commands.performServerConfiguration("server-password hunter2", on: session)

		#expect(lines == [String(localized: .IRC.configSecretOnCommandLine("/serverconfig server-password"))])
		#expect(session.recordedOutput.presentedAlerts.isEmpty)
		#expect(LocalCommand.lineCarriesSecret("/serverconfig server-password hunter2"))
		#expect(LocalCommand.lineCarriesSecret("/channelconfig #swift key letmein"))
		#expect(LocalCommand.lineCarriesSecret("/serverconfig nickname ada") == false)
	}

	@Test("A secret setting named alone is asked for in a secure field")
	func secretAsked() async throws {
		let session = session()
		session.recordedOutput.responseText = "hunter2"

		#expect(commands.performServerConfiguration("server-password", on: session).isEmpty)
		try await Eventually.until("the question") { session.recordedOutput.responseRequests.count == 1 }

		let question = try #require(session.recordedOutput.responseRequests.first)
		#expect(question.field?.isSecure == true)
		try await Eventually.until("the secret") {
			session.config.serverList.first?.pendingServerPassword == .edited("hunter2")
		}
	}

	@Test("An unknown setting points to the list, which names every setting")
	func unknownAndList() {
		let session = session()
		#expect(commands.performServerConfiguration("colour red", on: session)
			== [String(localized: .IRC.configUnknownSetting("colour", "/serverconfig list"))])
		let list = commands.performServerConfiguration("list", on: session)
		#expect(list.count == ServerConfigField.all.count + 1)
		#expect(Set(ServerConfigField.all.map(\.name)).count == ServerConfigField.all.count)
	}

	@Test("Lists take add, remove and clear")
	func lists() {
		let session = session()
		_ = commands.performServerConfiguration("connect-commands add /msg NickServ hello", on: session)
		_ = commands.performServerConfiguration("highlights add swift", on: session)
		#expect(session.config.loginCommands == ["/msg NickServ hello"])
		#expect(session.config.highlightList.map(\.matchKeyword) == ["swift"])

		_ = commands.performServerConfiguration("connect-commands remove 1", on: session)
		#expect(session.config.loginCommands.isEmpty)
	}

	@Test("Connect commands are counted, never printed")
	func connectCommandsStayUnprinted() {
		let session = session()
		let added = commands.performServerConfiguration(
			"connect-commands add /msg NickServ IDENTIFY hunter2", on: session
		)
		let listed = commands.performServerConfiguration("list", on: session)
		let shown = commands.performServerConfiguration("connect-commands", on: session)

		#expect(session.config.loginCommands == ["/msg NickServ IDENTIFY hunter2"])
		for line in added + listed + shown {
			#expect(line.contains("hunter2") == false)
			#expect(line.contains("IDENTIFY") == false)
		}
		#expect(LocalCommand.lineCarriesSecret("/serverconfig connect-commands add /msg NickServ IDENTIFY hunter2"))
	}

	@Test("Reset returns a setting to what a new server has")
	func reset() {
		let session = session()
		_ = commands.performServerConfiguration("autoreconnect on", on: session)
		_ = commands.performServerConfiguration("reset autoreconnect", on: session)
		#expect(session.config.autoReconnect == ServerConfig().autoReconnect)
	}

	@Test("Where the server is and whether TLS is on are set, never reset", arguments: [
		"address", "port", "tls", "transport", "websocket-path", "servers",
	])
	func endpointIsNotReset(_ name: String) {
		let session = session()
		let lines = commands.performServerConfiguration("reset \(name)", on: session)

		#expect(lines == [String(localized: .IRC.configNotResettable(name, "/serverconfig \(name)"))])
		#expect(session.config.serverList.first?.prefersSecuredConnection == true)
		#expect(session.config.serverList.first?.serverAddress == "irc.example.test")
	}

	@Test("/channelconfig changes a saved channel, the one typed in when none is named")
	func channelConfig() throws {
		let session = session()
		let channel = try #require(session.findConversationOrCreate("#swift"))
		var config = session.config
		config.conversationList = [channel.config]
		session.updateConfig(config)

		#expect(commands.performChannelConfiguration("events collapse", on: session, target: channel).count == 1)
		#expect(commands.performChannelConfiguration("#swift autojoin off", on: session, target: nil).count == 1)
		#expect(channel.config.generalEventMessageDisplay == .collapse)
		#expect(channel.config.autoJoin == false)
		#expect(commands.performChannelConfiguration("events loud", on: session, target: channel)
			== [String(localized: .IRC.configInvalidValue("events", "loud", "show | collapse | hide"))])
		#expect(commands.performChannelConfiguration("list", on: session, target: nil)
			== [String(localized: .IRC.channelConfigNeedsChannel)])
	}

	@Test("/setcolor takes #rrggbb or reset")
	func nicknameColor() {
		let nickname = "colortest\(UInt16.random(in: 0 ... 9999))"
		defer { NicknameColors.setOverride(nil, for: nickname) }

		#expect(commands.setNicknameColor("#ff8800", for: nickname)
			== [String(localized: .IRC.nicknameColorPinned(nickname, "#ff8800"))])
		#expect(NicknameColors.pinnedColor(for: nickname) != nil)
		#expect(commands.setNicknameColor("orange", for: nickname)
			== [String(localized: .IRC.nicknameColorInvalid("orange"))])
		_ = commands.setNicknameColor("reset", for: nickname)
		#expect(NicknameColors.pinnedColor(for: nickname) == nil)
	}
}
