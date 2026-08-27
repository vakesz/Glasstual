@testable import Glasstual
import XCTest

/** *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
class IRCNetworkListTests: XCTestCase {
	func testBundledListParses() {
		let list = NetworkList()

		XCTAssertGreaterThan(list.listOfNetworks.count, 20)

		for network in list.listOfNetworks {
			XCTAssertFalse(network.networkName.isEmpty)
			XCTAssertFalse(network.serverAddress.isEmpty, "\(network.networkName) has no address")

			XCTAssertNotEqual(network.serverPort, 0, "\(network.networkName) has no port")

			XCTAssertNotNil(network.networkDescription)
			XCTAssertNotNil(network.suggestedChannels)
		}
	}

	func testBundledListIsSortedAlphabetically() {
		let list = NetworkList()
		let networks = list.listOfNetworks

		for index in networks.indices.dropFirst() {
			let previous = networks[networks.index(before: index)]
			let current = networks[index]
			let result = previous.networkName.caseInsensitiveCompare(current.networkName)

			XCTAssertNotEqual(
				result,
				.orderedDescending,
				"\(previous.networkName) sorts after \(current.networkName)"
			)
		}
	}

	func testPopularSubsetIsPresentAndOrdered() {
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
			XCTAssertTrue(list.listOfNetworks.contains(network))
		}

		XCTAssertEqual(actual, expected)
	}

	func testDeadNetworksAreGone() {
		let list = NetworkList()
		let dead = [
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
		]

		for name in dead {
			XCTAssertNil(list.network(named: name), "\(name) should have been removed")
		}

		XCTAssertNil(list.network(withServerAddress: "chat.freenode.net"))
	}

	func testLiberaChatEntry() {
		let list = NetworkList()
		guard let libera = list.network(named: "libera.chat") else {
			return XCTFail("Missing Libera.Chat")
		}

		XCTAssertEqual(libera.serverAddress, "irc.libera.chat")

		XCTAssertEqual(libera.serverPort, 6697)

		XCTAssertTrue(libera.prefersSecuredConnection)
		XCTAssertTrue(libera.saslSupported)

		XCTAssertEqual(libera.registration, .optional)

		XCTAssertNotNil(libera.registrationNote)
		XCTAssertNotNil(libera.website)

		XCTAssertTrue(libera.accountFieldsApply)

		XCTAssertEqual(list.network(withServerAddress: "IRC.LIBERA.CHAT"), libera)
	}

	func testHybridIRCEntry() {
		let list = NetworkList()
		guard let hybridIRC = list.network(named: "HybridIRC") else {
			return XCTFail("Missing HybridIRC")
		}

		XCTAssertEqual(hybridIRC.serverAddress, "irc.hybridirc.com")

		XCTAssertEqual(hybridIRC.serverPort, 6697)

		XCTAssertTrue(hybridIRC.prefersSecuredConnection)
		XCTAssertTrue(hybridIRC.saslSupported)

		XCTAssertEqual(hybridIRC.registration, .optional)
	}

	func testHungarianDumaNetEntry() {
		let list = NetworkList()
		guard let dumaNet = list.network(named: "DumaNet") else {
			return XCTFail("Missing DumaNet")
		}

		XCTAssertEqual(dumaNet.serverAddress, "dumanet.hu")

		XCTAssertEqual(dumaNet.serverPort, 6697)

		XCTAssertTrue(dumaNet.prefersSecuredConnection)

		XCTAssertFalse(dumaNet.saslSupported)

		XCTAssertEqual(dumaNet.registration, .optional)

		XCTAssertTrue(dumaNet.suggestedChannels.contains("#help"))
	}

	func testNetworkWithoutServicesHidesAccountFields() {
		let list = NetworkList()
		guard let efnet = list.network(named: "EFnet") else {
			return XCTFail("Missing EFnet")
		}

		XCTAssertEqual(efnet.registration, .none)

		XCTAssertFalse(efnet.saslSupported)
		XCTAssertFalse(efnet.accountFieldsApply)
	}

	func testEntryWithoutAddressIsRejected() {
		let network = Network(dictionary: ["name": "Nowhere"])

		XCTAssertNil(network)
	}

	func testEntryDefaultsPortFromSecurity() {
		let secured = Network(dictionary: [
			"name": "A",
			"serverAddress": "a.example",
			"prefersSecuredConnection": true,
		])
		let plain = Network(dictionary: [
			"name": "B",
			"serverAddress": "b.example",
		])

		XCTAssertEqual(secured?.serverPort, 6697)
		XCTAssertEqual(plain?.serverPort, 6667)

		XCTAssertEqual(plain?.networkDescription, "")
		XCTAssertEqual(plain?.suggestedChannels, [])

		XCTAssertNil(plain?.registrationNote)
	}

	func testRegistrationParsing() {
		XCTAssertEqual(NetworkList.registration(from: "required"), .required)
		XCTAssertEqual(NetworkList.registration(from: "Optional"), .optional)
		XCTAssertEqual(NetworkList.registration(from: "none"), .none)
		XCTAssertEqual(NetworkList.registration(from: nil), .none)
		XCTAssertEqual(NetworkList.registration(from: "bogus"), .none)
	}

	func testAccountFieldsVisibility() {
		XCTAssertFalse(NetworkList.accountFieldsApply(to:
			.none,
			saslSupported: false))

		XCTAssertTrue(NetworkList.accountFieldsApply(to: .none, saslSupported: true))
		XCTAssertTrue(NetworkList.accountFieldsApply(to:
			.optional,
			saslSupported: false))
		XCTAssertTrue(NetworkList.accountFieldsApply(to:
			.optional,
			saslSupported: true))
		XCTAssertTrue(NetworkList.accountFieldsApply(to:
			.required,
			saslSupported: false))
		XCTAssertTrue(NetworkList.accountFieldsApply(to:
			.required,
			saslSupported: true))
	}

	func testOnboardingCompletedFlagRoundTrips() {
		let original: Bool = TextualPreferences.onboardingCompleted()

		TextualPreferences.setOnboardingCompleted(false)

		XCTAssertFalse(TextualPreferences.onboardingCompleted())

		TextualPreferences.setOnboardingCompleted(true)

		XCTAssertTrue(TextualPreferences.onboardingCompleted())

		TextualPreferences.setOnboardingCompleted(original)
	}
}
