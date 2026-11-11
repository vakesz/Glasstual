// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Server properties OAuth bearer token")
struct ServerPropertiesBearerTokenTests {
	@Test("A pending token fills the field and an untouched field submits no edit")
	func untouchedFieldSubmitsUnchanged() throws {
		var configuration = ServerConfig(connectionName: "Token")
		configuration.nickname = "me"
		configuration.username = "me"
		configuration.realName = "Me"
		configuration.serverList = [ServerEndpoint(serverAddress: "irc.example.net")]
		let model = ServerPropertiesModel(config: configuration)
		#expect(model.secretText(.saslBearerToken) == "")

		let submitted = try #require(model.submittedConfig())
		#expect(submitted.pendingSASLBearerToken == .unchanged)

		model.setSecretText("abc.def", for: .saslBearerToken)
		let edited = try #require(model.submittedConfig())
		#expect(edited.pendingSASLBearerToken == .edited("abc.def"))
	}

	@Test("A token with characters a bearer token cannot hold blocks saving")
	func invalidTokenBlocksSaving() {
		var configuration = ServerConfig(connectionName: "Token")
		configuration.nickname = "me"
		configuration.username = "me"
		configuration.realName = "Me"
		configuration.serverList = [ServerEndpoint(serverAddress: "irc.example.net")]
		let model = ServerPropertiesModel(config: configuration)

		model.setSecretText("not a token", for: .saslBearerToken)

		#expect(model.validationFault?.message == String(localized: .ServerProperties.saslBearerTokenInvalid))
		#expect(model.validationFault?.selection == .identity)
	}

	@Test("A token typed into the sheet makes OAUTHBEARER usable without a warning")
	func tokenSatisfiesTheMechanism() {
		let model = ServerPropertiesModel(config: ServerConfig(connectionName: "Token"))
		model.saslMechanismChoice = .mechanism(.oauthBearer)
		#expect(model.saslMechanismWarning?.hasPrefix(String(localized: .ServerProperties.saslMechanismMissingBearerToken)) == true)

		model.setSecretText("abc", for: .saslBearerToken)
		#expect(model.saslMechanismWarning == nil)
	}
}
