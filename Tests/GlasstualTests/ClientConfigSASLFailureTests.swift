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

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

/// A per-server "Disconnect if SASL authentication fails" option. Without it
/// the client completes registration unauthenticated on 904, 905 or 906, which
/// many networks treat as a security failure.
@Suite("Disconnect on SASL failure")
@MainActor
struct ClientConfigSASLFailureTests {
	private static let key = "disconnectOnSASLFailure"

	@Test("The option is off by default")
	func defaultsToOff() {
		#expect(IRCClientConfig().disconnectOnSASLFailure == false)
	}

	@Test("The setting can be turned on")
	func configSetsIt() {
		var config = IRCClientConfig()
		config.disconnectOnSASLFailure = true
		#expect(config.disconnectOnSASLFailure)
	}

	@Test("The value survives a round trip through the dictionary representation")
	func roundTripsThroughADictionary() throws {
		var config = IRCClientConfig()
		config.disconnectOnSASLFailure = true

		let dictionary = config.dictionaryValue
		#expect(dictionary[Self.key]?.boolean == true)

		let restored = try #require(PropertyListModel.decode(IRCClientConfig.self, from: dictionary))
		#expect(restored.disconnectOnSASLFailure)
	}

	@Test("A dictionary without the key reads back as off")
	func absentKeyReadsAsOff() throws {
		var dictionary = IRCClientConfig().dictionaryValue
		dictionary.removeValue(forKey: Self.key)

		let restored = try #require(PropertyListModel.decode(IRCClientConfig.self, from: dictionary))
		#expect(restored.disconnectOnSASLFailure == false)
	}

	@Test("An off value is not written to the dictionary")
	func offIsTheDefault() {
		#expect(IRCClientConfig().dictionaryValue[Self.key] == nil)
	}

	@Test("The numerics that mean SASL was refused are the ones the option acts on")
	func failureNumerics() {
		#expect(IRCNumeric.saslfail.rawValue == 904)
		#expect(IRCNumeric.sasltoolong.rawValue == 905)
		#expect(IRCNumeric.saslaborted.rawValue == 906)
	}

	@Test("The server-properties draft edits the setting directly")
	func sheetDraftCarriesTheSetting() {
		let model = ServerPropertiesModel(config: ClientConfig())
		model.config.disconnectOnSASLFailure = true
		#expect(model.config.disconnectOnSASLFailure)
	}

	@Test("The disconnect reason resolves against the string catalog")
	func disconnectReasonIsLocalized() {
		let reason = IRCInboundStrings.Numeric.saslAuthenticationFailedDisconnecting
		#expect(reason.isEmpty == false)
		#expect(reason != "sasl-authentication-failed-disconnecting")
	}
}
