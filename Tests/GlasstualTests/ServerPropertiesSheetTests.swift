/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Server properties sheet")
struct ServerPropertiesSheetTests {
	@Test("The form is native SwiftUI, not a nib-backed outlet graph")
	func formHasNoNib() {
		#expect(Bundle.main.path(forResource: "TDCServerPropertiesSheet", ofType: "nib") == nil)
	}

	@Test("The draft validates all persisted fields before submission")
	func draftValidation() throws {
		var config = ClientConfig(connectionName: "Libera")
		config.serverList = [Server(serverAddress: "irc.libera.chat", serverPort: 6697)]
		let model = ServerPropertiesModel(config: config)
		let submitted = try #require(model.submittedConfig())
		#expect(submitted.serverList.first?.serverAddress == "irc.libera.chat")
		model.serverPort = "70000"
		#expect(model.submittedConfig() == nil)
		#expect(model.selection == .general)
	}

	/// Emptying a secret used to write `nil` into the setter, which the keychain
	/// flush read as "nothing to do": the old password stayed in the keychain and
	/// the field read it straight back the next time the sheet opened.
	@Test("Emptying a secret asks for the keychain item to go")
	func emptiedSecretsAreCleared() throws {
		let model = ServerPropertiesModel(config: Self.configuration(withSecrets: true))
		#expect(model.nicknamePassword == "nick-secret")
		#expect(model.proxyPassword == "proxy-secret")
		#expect(model.serverPassword == "server-secret")

		model.nicknamePassword = ""
		model.proxyPassword = "  "
		model.serverPassword = ""
		let submitted = try #require(model.submittedConfig())

		#expect(submitted.pendingNicknamePassword == .cleared)
		#expect(submitted.pendingProxyPassword == .cleared)
		#expect(submitted.serverList.first?.pendingServerPassword == .cleared)
	}

	@Test("A secret left alone is written back rather than cleared")
	func untouchedSecretsSurviveSubmission() throws {
		let model = ServerPropertiesModel(config: Self.configuration(withSecrets: true))

		let submitted = try #require(model.submittedConfig())

		#expect(submitted.pendingNicknamePassword == .set("nick-secret"))
		#expect(submitted.pendingProxyPassword == .set("proxy-secret"))
		#expect(submitted.serverList.first?.pendingServerPassword == .set("server-secret"))
	}

	private static func configuration(withSecrets: Bool) -> ClientConfig {
		var config = ClientConfig(connectionName: "Libera")
		config.nickname = "someone"
		config.username = "someone"
		config.realName = "Someone"
		var server = Server(serverAddress: "irc.libera.chat", serverPort: 6697)
		if withSecrets {
			config.pendingNicknamePassword = .set("nick-secret")
			config.pendingProxyPassword = .set("proxy-secret")
			server.pendingServerPassword = .set("server-secret")
		}
		config.serverList = [server]

		return config
	}

	@Test("Identity fields accept what IRC accepts and nothing else")
	func identityValidationMatchesIRCRestrictions() {
		#expect(ServerPropertiesValidation.isNickname("valid_nick"))
		#expect(ServerPropertiesValidation.isNickname("invalid nickname") == false)
		#expect(ServerPropertiesValidation.isUsername("valid-user"))
		#expect(ServerPropertiesValidation.isUsername("invalid user") == false)
		#expect(ServerPropertiesValidation.areAlternateNicknamesValid(""))
		#expect(ServerPropertiesValidation.areAlternateNicknamesValid("   "))
		#expect(ServerPropertiesValidation.areAlternateNicknamesValid("first second"))
		#expect(ServerPropertiesValidation.areAlternateNicknamesValid("first invalid!nick") == false)
	}

	@Test("An endpoint needs a host that resolves as a name or an address, and a port in range")
	func endpointValidationRejectsInvalidAddressesAndPorts() {
		#expect(ServerPropertiesValidation.isInternetAddress("irc.libera.chat"))
		#expect(ServerPropertiesValidation.isInternetAddress("2001:db8::1"))
		#expect(ServerPropertiesValidation.isInternetAddress("not a host") == false)
		#expect(ServerPropertiesValidation.isInternetPort("6697"))
		#expect(ServerPropertiesValidation.isInternetPort("0") == false)
		#expect(ServerPropertiesValidation.isInternetPort("70000") == false)
	}

	@Test("A disconnect message stays inside the protocol's length limit and on one line")
	func disconnectMessageValidationPreservesProtocolLimit() {
		#expect(ServerPropertiesValidation.isLeavingComment(String(repeating: "a", count: 390)))
		#expect(ServerPropertiesValidation.isLeavingComment(String(repeating: "a", count: 391)) == false)
		#expect(ServerPropertiesValidation.isLeavingComment("first\nsecond") == false)
	}
}
