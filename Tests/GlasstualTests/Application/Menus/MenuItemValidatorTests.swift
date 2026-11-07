// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

/// Pins which channel- and member-menu commands are enabled for each kind of
/// selection, so the requirement table can be changed without changing a result.
@MainActor
@Suite("Menu item validator")
struct MenuItemValidatorTests {
	/// A kind of selection. Each case names the server and conversation state
	/// the validator is asked about.
	enum Scene: CaseIterable, Sendable {
		case none
		case disconnectedChannel
		case console
		case query
		case channelParted
		case channelJoined
		case channelJoinedOp
		case channelRestrictedTopic
		case consoleIRCop
		case channelJoinedIRCop
	}

	nonisolated static let scenes = Scene.allCases

	nonisolated static let channelCommands: [MenuCommand] = [
		.toggleFavorite, .joinChannel, .leaveChannel, .addChannel, .viewChannelLogs, .modifyTopic,
		.modes, .channelModeManageAll, .bans, .channelModeModerated, .channelModeInviteOnly,
		.channelProperties, .copyChannelIdentifier,
	]

	nonisolated static let ctcpCommands: [MenuCommand] = [
		.whois, .ctcp, .ctcpSendFile, .ctcpPing, .ctcpTime,
		.ctcpClientInfo, .ctcpVersion, .ctcpFinger, .ctcpUserInfo,
	]

	nonisolated static let operatorCommands: [MenuCommand] = [
		.ircOperator, .operatorSetVirtualHost, .operatorKill, .operatorShun, .operatorGline,
	]

	nonisolated static let memberCommands: [MenuCommand] = ctcpCommands + operatorCommands + [
		.inviteTo, .startDirectConversation, .changeColor, .ban, .kick, .kickban,
	]

	private struct Fixture {
		let controller = MenuActionController()
		let session = TestServerSession(configDictionary: ["nickname": "local"])
		let conversation: Conversation?
		let other: Conversation?

		init(_ scene: Scene) throws {
			session.userNickname = "local"
			controller.context.pointedSession = scene == .none ? nil : session
			if scene == .none {
				conversation = nil
				other = nil
				return
			}
			if scene != .disconnectedChannel {
				session.markAsLoggedIn()
			}
			session.userIsIRCop = scene == .consoleIRCop || scene == .channelJoinedIRCop
			other = session.findConversationOrCreate("#other")

			let selected: Conversation? = switch scene {
			case .console, .consoleIRCop: session.findConversationOrCreate("Server Traffic", isConsole: true)
			case .query: session.findConversationOrCreate("friend", isDirect: true)
			default: session.findConversationOrCreate("#chat")
			}
			conversation = selected
			controller.context.pointedConversation = selected

			switch scene {
			case .channelJoined, .channelJoinedOp, .channelRestrictedTopic, .channelJoinedIRCop:
				selected?.activate()
				selected?.addUser(session.findUserOrCreate("local"))
				if scene == .channelJoinedOp {
					selected?.changeMember("local", mode: ChannelModeSymbol(Character("o")), value: true)
				}
				if scene == .channelRestrictedTopic {
					_ = selected?.modeInfo?.updateModes("+t")
				}
			default:
				break
			}
		}

		func isEnabled(_ command: MenuCommand) -> (Bool, NSMenuItem) {
			let item = NSMenuItem()
			item.command = command
			let validator = controller.validator
			let result = command.validationGroup == .channel
				? validator.validateChannelCommand(item)
				: validator.validateMemberCommand(item)
			return (result, item)
		}
	}

	private static func expectedChannelCommands(_ scene: Scene) -> Set<MenuCommand> {
		let logs: Set<MenuCommand> = ApplicationPaths.isWritingTranscripts ? [.viewChannelLogs] : []
		switch scene {
		case .none:
			return []
		case .disconnectedChannel:
			return logs.union([.toggleFavorite, .addChannel, .channelProperties, .copyChannelIdentifier])
		case .console, .consoleIRCop:
			return logs.union([.addChannel, .copyChannelIdentifier])
		case .query:
			return logs.union([.toggleFavorite, .addChannel, .copyChannelIdentifier])
		case .channelParted:
			return logs.union([.toggleFavorite, .joinChannel, .addChannel, .channelProperties, .copyChannelIdentifier])
		case .channelJoined, .channelJoinedIRCop:
			return logs.union([
				.toggleFavorite, .leaveChannel, .addChannel, .bans, .modifyTopic,
				.channelProperties, .copyChannelIdentifier,
			])
		case .channelRestrictedTopic:
			return logs.union([
				.toggleFavorite, .leaveChannel, .addChannel, .bans,
				.channelProperties, .copyChannelIdentifier,
			])
		case .channelJoinedOp:
			return logs.union([
				.toggleFavorite, .leaveChannel, .addChannel, .bans, .modifyTopic,
				.modes, .channelModeManageAll, .channelModeModerated, .channelModeInviteOnly,
				.channelProperties, .copyChannelIdentifier,
			])
		}
	}

	private static func expectedMemberCommands(_ scene: Scene) -> Set<MenuCommand> {
		let people = Set(ctcpCommands)
		let operators = Set(operatorCommands)
		let management: Set<MenuCommand> = [.ban, .kick, .kickban]
		switch scene {
		case .none, .console:
			return []
		case .disconnectedChannel:
			return [.changeColor]
		case .consoleIRCop:
			return []
		case .query:
			return people.union([.inviteTo])
		case .channelParted:
			return people.union([.inviteTo, .startDirectConversation, .changeColor])
		case .channelJoined, .channelJoinedOp, .channelRestrictedTopic:
			return people.union(management).union([.inviteTo, .startDirectConversation, .changeColor])
		case .channelJoinedIRCop:
			return people.union(management).union(operators)
				.union([.inviteTo, .startDirectConversation, .changeColor])
		}
	}

	@Test("Channel commands are enabled only where the selection supports them", arguments: scenes)
	func channelCommandEnablement(scene: Scene) throws {
		let fixture = try Fixture(scene)
		let expected = Self.expectedChannelCommands(scene)
		for command in Self.channelCommands {
			let (enabled, _) = fixture.isEnabled(command)
			#expect(enabled == expected.contains(command), "\(command) in \(scene)")
		}
	}

	@Test("Member commands are enabled only where the selection supports them", arguments: scenes)
	func memberCommandEnablement(scene: Scene) throws {
		let fixture = try Fixture(scene)
		let expected = Self.expectedMemberCommands(scene)
		for command in Self.memberCommands {
			let (enabled, _) = fixture.isEnabled(command)
			#expect(enabled == expected.contains(command), "\(command) in \(scene)")
		}
	}

	@Test("Join and Leave show only the one that applies", arguments: scenes)
	func joinAndLeaveVisibility(scene: Scene) throws {
		let fixture = try Fixture(scene)
		let joined = fixture.isEnabled(.leaveChannel).0
		#expect(fixture.isEnabled(.joinChannel).1.isHidden == joined)
		#expect(fixture.isEnabled(.leaveChannel).1.isHidden == (joined == false))
	}

	@Test("The favorite item names the action it would take")
	func favoriteTitleFollowsState() throws {
		let fixture = try Fixture(.channelParted)
		let pin = fixture.isEnabled(.toggleFavorite).1.title
		let conversation = try #require(fixture.conversation)
		var config = conversation.config
		config.isFavorite = true
		conversation.updateConfig(config)
		let unpin = fixture.isEnabled(.toggleFavorite).1.title
		#expect(pin == String(localized: .Sidebar.pinFavorite))
		#expect(unpin == String(localized: .Sidebar.unpinFavorite))
	}

	@Test("Mode toggles tick while their mode is set")
	func modeTogglesTickWhenSet() throws {
		let fixture = try Fixture(.channelJoinedOp)
		#expect(fixture.isEnabled(.channelModeModerated).1.state == .off)
		#expect(fixture.isEnabled(.channelModeInviteOnly).1.state == .off)
		_ = fixture.conversation?.modeInfo?.updateModes("+mi")
		#expect(fixture.isEnabled(.channelModeModerated).1.state == .on)
		#expect(fixture.isEnabled(.channelModeInviteOnly).1.state == .on)
	}

	@Test("List commands follow the server's list support while joined")
	func listCommandsFollowServerSupport() throws {
		let fixture = try Fixture(.channelJoined)
		let lists: [(MenuCommand, ISupportListKind)] = [
			(.banExceptions, .banException), (.inviteExceptions, .inviteException), (.quiets, .quiet),
		]
		for (command, kind) in lists {
			#expect(fixture.isEnabled(command).0 == fixture.session.supportInfo.isListSupported(kind))
		}
		fixture.session.supportInfo.processConfigurationData("EXCEPTS=e INVEX=I")
		#expect(fixture.isEnabled(.banExceptions).0)
		#expect(fixture.isEnabled(.inviteExceptions).0)
		let parted = try Fixture(.channelParted)
		parted.session.supportInfo.processConfigurationData("EXCEPTS=e INVEX=I")
		#expect(parted.isEnabled(.banExceptions).0 == false)
		#expect(parted.isEnabled(.inviteExceptions).0 == false)
		#expect(parted.isEnabled(.quiets).0 == false)
	}

	// MARK: Member selections

	private func member(_ name: String, modes: String = "", hostmask: Bool = false) -> Member {
		var user = User(nickname: name)
		if hostmask {
			user.username = "ident"
			user.address = "host.example"
		}
		var member = Member(user: user, prefixes: UserPrefixTable())
		member.modes = ChannelModeSymbolSet(letters: modes)
		return member
	}

	struct RankCase: Sendable {
		let label: String
		let modes: [String]
		let enabled: Set<MenuCommand>
	}

	nonisolated static let rankCases: [RankCase] = [
		RankCase(label: "no rank", modes: [""], enabled: [.giveOp, .giveVoice]),
		RankCase(label: "voiced", modes: ["v"], enabled: [.giveOp, .takeVoice]),
		RankCase(label: "operator", modes: ["o"], enabled: [.takeOp, .giveVoice]),
		RankCase(label: "multiple", modes: ["o", "v"], enabled: [.giveOp, .takeOp, .giveVoice, .takeVoice]),
		RankCase(label: "none selected", modes: [], enabled: []),
	]

	nonisolated static let rankCommands: [MenuCommand] = [.giveOp, .takeOp, .giveVoice, .takeVoice]

	@Test("Rank commands compare against a single member and apply to a multiple selection", arguments: rankCases)
	func rankCommands(rankCase: RankCase) throws {
		let fixture = try Fixture(.channelJoined)
		let members = rankCase.modes.enumerated().map { member("user\($0.offset)", modes: $0.element) }
		fixture.controller.context.withContext(.members(members)) {
			for command in Self.rankCommands {
				#expect(
					fixture.controller.validator.validateMemberCommand(menuItem(command)) == rankCase.enabled.contains(command),
					"\(command) for \(rankCase.label)"
				)
			}
		}
	}

	@Test("Rank commands need an active channel on a registered connection", arguments: [Scene.none, .console, .query, .channelParted])
	func rankCommandsNeedActiveChannel(scene: Scene) throws {
		let fixture = try Fixture(scene)
		fixture.controller.context.withContext(.members([member("alice")])) {
			for command in Self.rankCommands + [.giveHalfop, .takeHalfop] {
				#expect(fixture.controller.validator.validateMemberCommand(menuItem(command)) == false, "\(command)")
			}
		}
	}

	@Test("Half-op commands need the server to know the rank")
	func halfOpCommandsFollowPrefixSupport() throws {
		let fixture = try Fixture(.channelJoined)
		let supported = fixture.session.supportInfo.modeSymbolIsUserPrefix("h")
		fixture.controller.context.withContext(.members([member("alice")])) {
			#expect(fixture.controller.validator.validateMemberCommand(menuItem(.giveHalfop)) == supported)
			#expect(fixture.controller.validator.validateMemberCommand(menuItem(.takeHalfop)) == false)
		}
		fixture.session.supportInfo.processConfigurationData("PREFIX=(qaohv)~&@%+")
		fixture.controller.context.withContext(.members([member("alice"), member("bob")])) {
			#expect(fixture.controller.validator.validateMemberCommand(menuItem(.giveHalfop)))
			#expect(fixture.controller.validator.validateMemberCommand(menuItem(.takeHalfop)))
		}
		fixture.controller.context.withContext(.members([member("alice", modes: "h")])) {
			#expect(fixture.controller.validator.validateMemberCommand(menuItem(.giveHalfop)) == false)
			#expect(fixture.controller.validator.validateMemberCommand(menuItem(.takeHalfop)))
		}
	}

	private func menuItem(_ command: MenuCommand) -> NSMenuItem {
		let item = NSMenuItem()
		item.command = command
		return item
	}

	@Test("Ignore commands need one member with a hostmask and follow the existing entry")
	func ignoreCommandsFollowEntry() throws {
		let fixture = try Fixture(.channelJoined)
		let validator = fixture.controller.validator
		func results() -> [Bool] {
			[MenuCommand.addIgnore, .modifyIgnore, .removeIgnore].map { validator.validateMemberCommand(menuItem($0)) }
		}

		fixture.controller.context.withContext(.members([member("alice", hostmask: true)])) {
			#expect(results() == [true, false, false])
		}
		fixture.controller.context.withContext(.members([member("alice")])) {
			#expect(results() == [false, false, false])
		}
		fixture.controller.context.withContext(.members([member("alice", hostmask: true), member("bob", hostmask: true)])) {
			#expect(results() == [false, false, false])
		}
		fixture.controller.context.withContext(.members([])) {
			#expect(results() == [false, false, false])
		}

		var configuration = fixture.session.config
		configuration.ignoreList = [AddressBookEntry.newIgnoreEntry(forHostmask: "alice!*@*")]
		fixture.session.updateConfig(configuration)
		fixture.controller.context.withContext(.members([member("alice", hostmask: true)])) {
			#expect(results() == [false, true, true])
		}

		let console = try Fixture(.console)
		console.controller.context.withContext(.members([member("alice", hostmask: true)])) {
			#expect([MenuCommand.addIgnore, .modifyIgnore, .removeIgnore].map {
				console.controller.validator.validateMemberCommand(menuItem($0))
			} == [false, false, false])
		}
	}
}
