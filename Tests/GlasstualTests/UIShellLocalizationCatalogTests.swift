/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("UI shell localized copy")
struct UIShellLocalizationCatalogTests {
	@Test("Onboarding copy is resolved by role, and its counted step is formatted")
	func onboardingBoundaryResolvesSemanticCopyAndFormatting() {
		#expect(OnboardingStrings.Window.title == "Welcome to Glasstual")
		#expect(OnboardingStrings.Window.progress(currentStep: 2, totalSteps: 4) == "Step 2 of 4")
		#expect(OnboardingStrings.Identity.nicknameLabel == "Nickname:")
		#expect(
			OnboardingStrings.Identity.alternateNicknameHelp ==
				"Used when your nickname is already taken. Optional."
		)
		#expect(OnboardingStrings.Appearance.textSizeTitles == ["Small", "Medium", "Large"])
		#expect(OnboardingStrings.Appearance.interfaceStyleTitles == ["System", "Light", "Dark"])
		#expect(OnboardingStrings.Appearance.previewMessages == [
			.init(nickname: "alice", message: "Good morning everyone"),
			.init(nickname: "bob", message: "Morning! Anyone tried the new build?"),
			.init(nickname: "you", message: "Yes, it works well so far."),
		])
		#expect(OnboardingStrings.Notifications.permissionGranted == "Notifications are allowed for Glasstual.")
		#expect(OnboardingStrings.FirstNetwork.suggestedChannelsLabel == "Suggested channels:")
		#expect(OnboardingStrings.NetworkPicker.customServerTitle == "Custom Server…")
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
				ServerPropertiesStrings.Navigation.serverProperties,
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
				ServerPropertiesStrings.Navigation.redundancy,
			] == [
				"Server Properties", "Vendor Specific", "Advanced", "Address Book", "Channel List",
				"Connect Commands", "Encoding", "General", "Identity", "Highlights", "Messages",
				"ZNC Bouncer", "Client Certificate", "Flood Control", "Network Socket", "Proxy Server",
				"Redundancy",
			]
		)
		#expect(
			ServerPropertiesStrings.Validation.invalidAlternateNickname("bad nick") ==
				"""
				Please enter a list of properly formatted nicknames.

				Failed on nickname: “bad nick“

				List of nicknames should be space separated.
				For example: “Guest1 Guest2 Guest3“
				"""
		)
		#expect(
			ServerPropertiesStrings.CipherSuites.description("TLS_AES_256_GCM_SHA384") ==
				"TLS_AES_256_GCM_SHA384\n\nThese cipher suites are ordered by preference with the most "
				+ "preferred at the top."
		)
		#expect(
			ServerPropertiesStrings.ExternalChange.unsavedChangesWarning ==
				"You will loose unsaved changes if you click “Yes”"
		)
	}

	@Test("Main window copy is keyed by the typed status and the typed member rank")
	func mainWindowBoundaryUsesTypedStatusAndRankMappings() {
		#expect(MainWindowStrings.MemberList.privilegeDescription(for: .normalOperator) == "Operator")
		#expect(MainWindowStrings.MemberList.privilegeDescription(for: .none) == "No Privileges")
		#expect(MainWindowStrings.MemberList.sectionTitle(for: .irCopByMode) == "Server Staff")
		#expect(MainWindowStrings.MemberList.sectionTitle(for: .none) == "Members")
		#expect(MainWindowStrings.MemberList.loggedIn(account: "alice") == "Logged in as alice")
		#expect(MainWindowStrings.ConnectionStatus.disconnected.title == "Disconnected")
		#expect(MainWindowStrings.ConnectionStatus.waitingToReconnect.title == "Waiting to reconnect")
		#expect(MainWindowStrings.ConnectionStatus.connecting.title == "Connecting")
		#expect(MainWindowStrings.ConnectionStatus.reconnecting.title == "Reconnecting")
		#expect(MainWindowStrings.ConnectionStatus.loggingOn.title == "Logging on")
		#expect(MainWindowStrings.ConnectionStatus.disconnecting.title == "Disconnecting")
		#expect(MainWindowStrings.Conversation.userCount("1,234") == "1,234 users")
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
			"TDCOnboardingWindow": ["window-chrome-step": "Step %1$ld of %2$ld"],
			"TDCServerPropertiesSheet": [
				"these-cipher-suites-are-ordered":
					"%@\n\nThese cipher suites are ordered by preference with the most preferred at the top.",
				"please-enter-a-list-of-properly":
					"Please enter a list of properly formatted nicknames.\n\n"
					+ "Failed on nickname: “%@“\n\n"
					+ "List of nicknames should be space separated.\n"
					+ "For example: “Guest1 Guest2 Guest3“",
				"includes-the-following-cipher-suites": "The “%@” includes the following cipher suites:",
			],
			"TVCMainWindow": [
				"member-account-status-description-logged": "Logged in as %@",
				"dock-icon-badge-shown": "%@+",
				"input-bar-reply-banner-replying": "Replying to %@",
				"main-window-connection-status-users": "%@ users",
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

	private func catalog(named tableName: String) throws -> UIShellCatalog {
		try JSONDecoder().decode(
			UIShellCatalog.self,
			from: Data(contentsOf: languageFilesURL.appending(path: "\(tableName).xcstrings"))
		)
	}

	private var languageFilesURL: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Sources/App/Resources/Language Files")
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
