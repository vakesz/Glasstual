import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/** *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */
@MainActor
@Suite("Bundled network list", .serialized)
struct IRCNetworkListTests {
	@Test("Every bundled entry parses with a name, an address and a port")
	func bundledListParses() {
		let list = NetworkList()

		#expect(list.listOfNetworks.count > 20)

		for network in list.listOfNetworks {
			#expect(network.networkName.isEmpty == false)
			#expect(network.serverAddress.isEmpty == false, "\(network.networkName) has no address")
			#expect(network.serverPort != 0, "\(network.networkName) has no port")
		}
	}

	@Test("The bundled list is sorted alphabetically, ignoring case")
	func bundledListIsSortedAlphabetically() {
		let list = NetworkList()
		let networks = list.listOfNetworks

		for index in networks.indices.dropFirst() {
			let previous = networks[networks.index(before: index)]
			let current = networks[index]
			let result = previous.networkName.caseInsensitiveCompare(current.networkName)

			#expect(
				result != .orderedDescending,
				"\(previous.networkName) sorts after \(current.networkName)"
			)
		}
	}

	@Test("The popular subset is drawn from the full list and keeps its curated order")
	func popularSubsetIsPresentAndOrdered() {
		let list = NetworkList()
		let expected = [
			"Libera.Chat",
			"HybridIRC",
			"IRCnet",
			"Undernet",
			"OFTC",
			"Rizon",
			"EFnet",
			"DALnet",
			"QuakeNet",
			"hackint",
			"Snoonet",
			"Tilde.Chat",
			"DumaNet",
		]
		var actual: [String] = []

		for network in list.popularNetworks {
			actual.append(network.networkName)
			#expect(list.listOfNetworks.contains(network))
		}

		#expect(actual == expected)
	}

	@Test("A network that has shut down is no longer offered", arguments: [
		"freenode",
		"PonyChat",
		"IdleChat",
		"GeeksIRC",
		"NixtrixIRC",
		"Mozor",
		"Thinkstack",
		"StormBit",
		"Snyde",
		"Mibbit",
		"Ewnix",
		"TinyCrab",
	])
	func deadNetworksAreGone(_ name: String) {
		#expect(NetworkList().network(named: name) == nil, "\(name) should have been removed")
	}

	@Test("The address of a network that has shut down no longer resolves")
	func deadNetworkAddressesAreGone() {
		#expect(NetworkList().network(withServerAddress: "chat.freenode.net") == nil)
	}

	@Test("Libera.Chat is offered secured, with SASL and an address lookup that ignores case")
	func liberaChatEntry() throws {
		let list = NetworkList()
		let libera = try #require(list.network(named: "libera.chat"), "Missing Libera.Chat")

		#expect(libera.serverAddress == "irc.libera.chat")
		#expect(libera.serverPort == 6697)
		#expect(libera.prefersSecuredConnection)
		#expect(libera.saslSupported)
		#expect(libera.registration == .optional)
		#expect(libera.registrationNote != nil)
		#expect(libera.website != nil)
		#expect(libera.accountFieldsApply)
		#expect(list.network(withServerAddress: "IRC.LIBERA.CHAT") == libera)
	}

	@Test("HybridIRC is offered secured and with SASL")
	func hybridIRCEntry() throws {
		let list = NetworkList()
		let hybridIRC = try #require(list.network(named: "HybridIRC"), "Missing HybridIRC")

		#expect(hybridIRC.serverAddress == "irc.hybridirc.com")
		#expect(hybridIRC.serverPort == 6697)
		#expect(hybridIRC.prefersSecuredConnection)
		#expect(hybridIRC.saslSupported)
		#expect(hybridIRC.registration == .optional)
	}

	@Test("DumaNet is offered secured, without SASL, and suggests its help channel")
	func hungarianDumaNetEntry() throws {
		let list = NetworkList()
		let dumaNet = try #require(list.network(named: "DumaNet"), "Missing DumaNet")

		#expect(dumaNet.serverAddress == "dumanet.hu")
		#expect(dumaNet.serverPort == 6697)
		#expect(dumaNet.prefersSecuredConnection)
		#expect(dumaNet.saslSupported == false)
		#expect(dumaNet.registration == .optional)
		#expect(dumaNet.suggestedChannels.contains("#help"))
	}

	@Test("A network with no services at all hides the account fields")
	func networkWithoutServicesHidesAccountFields() throws {
		let list = NetworkList()
		let efnet = try #require(list.network(named: "EFnet"), "Missing EFnet")

		#expect(efnet.registration == .none)
		#expect(efnet.saslSupported == false)
		#expect(efnet.accountFieldsApply == false)
	}

	@Test("An entry without a server address is not a network")
	func entryWithoutAddressIsRejected() {
		let network = Network(dictionary: ["name": "Nowhere"])

		#expect(network == nil)
	}

	@Test("An entry without a port takes the port its security setting implies")
	func entryDefaultsPortFromSecurity() {
		let secured = Network(dictionary: [
			"name": "A",
			"serverAddress": "a.example",
			"prefersSecuredConnection": true,
		])
		let plain = Network(dictionary: [
			"name": "B",
			"serverAddress": "b.example",
		])

		#expect(secured?.serverPort == 6697)
		#expect(plain?.serverPort == 6667)
		#expect(plain?.networkDescription == "")
		#expect(plain?.suggestedChannels == [])
		#expect(plain?.registrationNote == nil)
	}

	@Test("A registration string maps to its case, and anything else means none", arguments: [
		("required", IRCNetworkRegistration.required),
		("Optional", .optional),
		("none", .none),
		(nil, .none),
		("bogus", .none),
	] as [(String?, IRCNetworkRegistration)])
	func registrationParsing(_ string: String?, _ expected: IRCNetworkRegistration) {
		#expect(NetworkList.registration(from: string) == expected)
	}

	@Test("A network with neither services nor SASL hides the account fields")
	func accountFieldsAreHiddenWithoutServices() {
		#expect(NetworkList.accountFieldsApply(to: .none, saslSupported: false) == false)
	}

	@Test("Services or SASL alone is enough to show the account fields", arguments: [
		(IRCNetworkRegistration.none, true),
		(.optional, false),
		(.optional, true),
		(.required, false),
		(.required, true),
	])
	func accountFieldsAreShownWithServicesOrSASL(
		_ registration: IRCNetworkRegistration,
		_ saslSupported: Bool
	) {
		#expect(NetworkList.accountFieldsApply(to: registration, saslSupported: saslSupported))
	}

	@Test("The onboarding flag round trips through the preference store")
	func onboardingCompletedFlagRoundTrips() {
		let original: Bool = TextualPreferences.onboardingCompleted()

		TextualPreferences.setOnboardingCompleted(false)

		#expect(TextualPreferences.onboardingCompleted() == false)

		TextualPreferences.setOnboardingCompleted(true)

		#expect(TextualPreferences.onboardingCompleted())

		TextualPreferences.setOnboardingCompleted(original)
	}
}
