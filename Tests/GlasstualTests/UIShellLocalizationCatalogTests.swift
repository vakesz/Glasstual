/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("UI shell localized copy")
struct UIShellLocalizationCatalogTests {
	@Test("Onboarding copy is resolved by role, and its counted step is formatted")
	func onboardingBoundaryResolvesSemanticCopyAndFormatting() {
		#expect(OnboardingStrings.Window.title == "Welcome to Glasstual")
		#expect(OnboardingStrings.Window.progress(currentStep: 2, totalSteps: 4) == "Step 2 of 4")
		#expect(OnboardingStrings.Identity.nicknameLabel == "Nickname")
		#expect(
			OnboardingStrings.Identity.alternateNicknameHelp ==
				"Used when your nickname is already taken. Optional."
		)
		#expect(OnboardingTextSize.allCases.map(\.title) == ["Small", "Medium", "Large"])
		#expect(
			PreferredAppearance.allCases.map(OnboardingStrings.Appearance.interfaceStyleTitle)
				== ["System", "Light", "Dark"]
		)
		#expect(OnboardingStrings.Appearance.previewMessages == [
			.init(nickname: "alice", message: "Good morning everyone"),
			.init(nickname: "bob", message: "Morning! Anyone tried the new build?"),
			.init(nickname: "you", message: "Yes, it works well so far."),
		])
		#expect(OnboardingStrings.Notifications.permissionGranted == "Notifications are allowed for Glasstual.")
		#expect(OnboardingStrings.FirstNetwork.suggestedChannelsLabel == "Suggested channels")
		#expect(OnboardingStrings.NetworkPicker.customServerTitle == "Custom Server")
		#expect(OnboardingStrings.NetworkPicker.invalidPort == "Enter a port between 1 and 65535.")
	}

	@Test("Server properties copy is keyed by domain types and keeps its multiline shape")
	func serverPropertiesBoundaryUsesDomainTypesAndPreservesMultilineCopy() {
		#expect(ServerPropertiesStrings.AddressBook.entryType(.ignore) == "User Ignore")
		#expect(ServerPropertiesStrings.AddressBook.entryType(.userTracking) == "User Tracking")
		#expect(ServerPropertiesStrings.Highlight.matchType(isExcluded: true) == "Exclude")
		#expect(ServerPropertiesStrings.Highlight.matchType(isExcluded: false) == "Match")
		#expect(
			[
				ServerPropertiesStrings.Navigation.connection,
				ServerPropertiesStrings.Navigation.vendorSpecific,
				ServerPropertiesStrings.Navigation.advanced,
				ServerPropertiesStrings.Navigation.addressBook,
				ServerPropertiesStrings.Navigation.channelList,
				ServerPropertiesStrings.Navigation.connectCommands,
				ServerPropertiesStrings.Navigation.encoding,
				ServerPropertiesStrings.Navigation.general,
				ServerPropertiesStrings.Navigation.identity,
				ServerPropertiesStrings.Navigation.highlights,
				ServerPropertiesStrings.Navigation.messages,
				ServerPropertiesStrings.Navigation.zncBouncer,
				ServerPropertiesStrings.Navigation.clientCertificate,
				ServerPropertiesStrings.Navigation.floodControl,
				ServerPropertiesStrings.Navigation.networkSocket,
				ServerPropertiesStrings.Navigation.proxyServer,
			] == [
				"Connection", "Vendor Specific", "Advanced", "Address Book", "Channel List",
				"Connect Commands", "Encoding", "General", "Identity", "Highlights", "Messages",
				"ZNC Bouncer", "Client Certificate", "Flood Control", "Network Socket", "Proxy Server",
			]
		)
		#expect(
			ServerPropertiesStrings.Validation.invalidAlternateNickname("bad nick") ==
				"“bad nick” is not a valid nickname. Separate alternative nicknames with spaces, "
				+ "for example: Guest1 Guest2 Guest3"
		)
		#expect(
			ServerPropertiesStrings.CipherSuites.listExplanation(collectionName: "Default list") ==
				"The “Default list” prefers these cipher suites, most preferred first."
		)
		/* The alert asks whether to reload, and its buttons are Cancel and
		 Reload -- so the body cannot name a "Yes" button that is not there. */
		#expect(ServerPropertiesStrings.ExternalChange.reloadTitle == "Reload the connection’s settings?")
		#expect(
			ServerPropertiesStrings.ExternalChange.unsavedChangesWarning ==
				"Your unsaved changes will be discarded."
		)
	}

	@Test("Main window copy is keyed by the typed status and the typed member rank")
	func mainWindowBoundaryUsesTypedStatusAndRankMappings() {
		#expect(MemberListStrings.privilegeDescription(for: .normalOperator) == "Operator")
		/* A rank column reads down; "No Privileges" was a sentence where every
		 other row held a word. */
		#expect(MemberListStrings.privilegeDescription(for: .none) == "None")
		/* One name per concept: the privilege and the section a server operator
		 is grouped under used to disagree with each other. */
		#expect(MemberListStrings.privilegeDescription(for: .irCopByMode) == "Server Staff")
		#expect(MemberListStrings.privilegeDescription(for: .superOperator) == "Admin")
		#expect(MemberListStrings.sectionTitle(for: .superOperator) == "Admins")
		#expect(MemberListStrings.privilegeDescription(for: .halfOperator) == "Half-Operator")
		#expect(MemberListStrings.sectionTitle(for: .halfOperator) == "Half-Operators")
		#expect(MemberListStrings.sectionTitle(for: .irCopByMode) == "Server Staff")
		#expect(MemberListStrings.sectionTitle(for: .none) == "Members")
		#expect(MemberListStrings.loggedIn(account: "alice") == "Logged in as alice")
		#expect(MainWindowStrings.ConnectionStatus.disconnected.title == "Disconnected")
		#expect(MainWindowStrings.ConnectionStatus.waitingToReconnect.title == "Waiting to reconnect")
		#expect(MainWindowStrings.ConnectionStatus.connecting.title == "Connecting")
		#expect(MainWindowStrings.ConnectionStatus.reconnecting.title == "Reconnecting")
		#expect(MainWindowStrings.ConnectionStatus.loggingOn.title == "Logging on")
		#expect(MainWindowStrings.ConnectionStatus.disconnecting.title == "Disconnecting")
		/* "1 users" was the subtitle of every one-member channel; the digits
		 are still grouped the way the reader's locale groups them. */
		#expect(MainWindowStrings.Conversation.memberCount(1) == "1 member")
		#expect(
			MainWindowStrings.Conversation.memberCount(1234)
				== "\(1234.formatted(.number)) members"
		)
		#expect(MainWindowStrings.Conversation.awayNickname("alice") == "alice (away)")
		#expect(MainWindowStrings.Menu.serverList(isVisible: false) == "Show Server List")
		#expect(MainWindowStrings.Menu.serverList(isVisible: true) == "Hide Server List")
		#expect(MainWindowStrings.Menu.memberList(isVisible: false) == "Show Member List")
		#expect(MainWindowStrings.Menu.memberList(isVisible: true) == "Hide Member List")
		#expect(MainWindowStrings.Dock.overflowBadge(maximum: "9,999") == "9,999+")
		#expect(MainWindowStrings.Reply.target(nil) == "Replying to a message")
		#expect(MainWindowStrings.Reply.target("alice") == "Replying to alice")
		#expect(MainWindowStrings.Typing.caption(for: ["alice"]) == "alice is typing…")
		#expect(MainWindowStrings.Typing.caption(for: ["alice", "bob"]) == "alice and bob are typing…")
		#expect(MainWindowStrings.Typing.caption(for: ["alice", "bob", "carol"]) == "3 people are typing…")
	}

	/// The placeholder contract of the multi-argument entries, which is what a
	/// careless catalog edit actually breaks. Everything structural about
	/// these tables is covered by `StringCatalogStructureTests`.
	@Test("Multi-argument entries keep their placeholder contracts")
	func multiArgumentValuesKeepTheirPlaceholderContracts() throws {
		let expectedValues = [
			"Onboarding": ["window-chrome-step": "Step %1$ld of %2$ld"],
			"ServerProperties": [
				"please-enter-a-list-of-properly":
					"“%@” is not a valid nickname. Separate alternative nicknames with spaces, "
					+ "for example: Guest1 Guest2 Guest3",
				"includes-the-following-cipher-suites":
					"The “%@” prefers these cipher suites, most preferred first.",
				"copy-nickserv-command-for": "Copy NickServ Command for %@",
			],
			"ChannelProperties": [
				"secret-key-length": "%1$ld of %2$ld bytes",
				"secret-key-too-long":
					"%1$@ accepts at most %2$ld bytes. Anything past that may be cut off.",
			],
			/* The member-list entries moved into the feature's own catalog with
				the list itself. */
			"MemberList": [
				"logged-in-as": "Logged in as %@",
			],
			"MainWindow": [
				"dock-icon-badge-shown": "%@+",
				"input-bar-reply-banner-replying": "Replying to %@",
				/* The count twice: as text for the digits, as a number for the
					noun's plural form. */
				"main-window-connection-status-users": "%1$@ %#@count@",
				"is-typing": "%@ is typing…",
				"are-typing": "%@ and %@ are typing…",
			],
		]

		for (tableName, values) in expectedValues {
			let catalog = try catalog(named: tableName)
			for (key, expectedValue) in values {
				#expect(
					catalog.strings[key]?.localizations["en"]?.stringUnit?.value == expectedValue,
					"\(tableName):\(key)"
				)
			}
		}
	}

	/// A catalog lives beside the feature that owns it, so it is found by its
	/// own name rather than in one fixed directory.
	private func catalog(named tableName: String) throws -> UIShellCatalog {
		let sourcesURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Sources/App")
		guard let walker = FileManager.default.enumerator(at: sourcesURL, includingPropertiesForKeys: nil) else {
			throw CatalogLookupError.notFound(tableName)
		}

		for case let url as URL in walker where url.lastPathComponent == "\(tableName).xcstrings" {
			return try JSONDecoder().decode(UIShellCatalog.self, from: Data(contentsOf: url))
		}

		throw CatalogLookupError.notFound(tableName)
	}

	private enum CatalogLookupError: Error {
		case notFound(String)
	}
}

private struct UIShellCatalog: Decodable {
	let sourceLanguage: String
	let strings: [String: UIShellCatalogEntry]
	let version: String
}

private struct UIShellCatalogEntry: Decodable {
	let comment: String
	let extractionState: String
	let localizations: [String: UIShellCatalogLocalization]
}

private struct UIShellCatalogLocalization: Decodable {
	/// Absent on entries that carry plural variations instead.
	let stringUnit: UIShellCatalogStringUnit?
}

private struct UIShellCatalogStringUnit: Decodable {
	let state: String
	let value: String
}
