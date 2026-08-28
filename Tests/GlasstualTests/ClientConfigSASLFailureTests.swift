/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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
struct ClientConfigSASLFailureTests {
	private static let key = "disconnectOnSASLFailure"

	@Test("The option is off by default")
	func defaultsToOff() {
		#expect(IRCClientConfig().disconnectOnSASLFailure == false)
	}

	@Test("The mutable config carries the setter")
	func mutableConfigSetsIt() {
		let config = IRCClientConfigMutable()
		config.disconnectOnSASLFailure = true
		#expect(config.disconnectOnSASLFailure)
	}

	@Test("The value survives a round trip through the dictionary representation")
	func roundTripsThroughADictionary() {
		let config = IRCClientConfigMutable()
		config.disconnectOnSASLFailure = true

		let dictionary = config.dictionaryValue(for: .default)
		#expect(dictionary[Self.key] as? Bool == true)

		let restored = IRCClientConfig(dictionary: dictionary)
		#expect(restored.disconnectOnSASLFailure)
	}

	@Test("A dictionary without the key reads back as off")
	func absentKeyReadsAsOff() {
		var dictionary = IRCClientConfigMutable().dictionaryValue(for: .default)
		dictionary.removeValue(forKey: Self.key)

		#expect(IRCClientConfig(dictionary: dictionary).disconnectOnSASLFailure == false)
	}

	@Test("An off value is not written to the dictionary")
	func offIsTheDefault() {
		#expect(IRCClientConfig().dictionaryValue(for: .default)[Self.key] == nil)
	}

	@Test("The numerics that mean SASL was refused are the ones the option acts on")
	func failureNumerics() {
		#expect(IRCNumeric.saslfail.rawValue == 904)
		#expect(IRCNumeric.sasltoolong.rawValue == 905)
		#expect(IRCNumeric.saslaborted.rawValue == 906)
	}

	@Test("The sheet exposes the checkbox the nib connects")
	@MainActor
	func sheetDeclaresTheOutlet() {
		#expect(
			ServerPropertiesSheet.instancesRespond(to: NSSelectorFromString("disconnectOnSASLFailureCheck"))
		)
	}

	@Test("The disconnect reason resolves against the string catalog")
	func disconnectReasonIsLocalized() {
		let reason = IRCInboundStrings.Numeric.saslAuthenticationFailedDisconnecting
		#expect(reason.isEmpty == false)
		#expect(reason != "sasl-authentication-failed-disconnecting")
	}
}
