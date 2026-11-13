// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Bouncer network set")
struct BouncerNetworkSetTests {
	private func network(_ id: String, _ name: String, state: BouncerNetwork.State? = nil) -> BouncerNetwork {
		BouncerNetwork(id: id, name: name, state: state)
	}

	@Test("The first listing adds every network and names the whole listing")
	func firstSnapshotAddsEverything() {
		var set = BouncerNetworkSet()

		let changes = set.apply(.snapshot([network("1", "A"), network("2", "B")]))

		#expect(changes.added.map(\.id) == ["1", "2"])
		#expect(changes.changed.isEmpty)
		#expect(changes.removed.isEmpty)
		#expect(changes.completeListing == ["1", "2"])
		#expect(set.networks.map(\.id) == ["1", "2"])
	}

	@Test("A later listing reports what was added, changed and removed")
	func snapshotDiff() {
		var set = BouncerNetworkSet()
		_ = set.apply(.snapshot([network("1", "A"), network("2", "B"), network("3", "C")]))

		let changes = set.apply(.snapshot([network("2", "B renamed"), network("3", "C"), network("4", "D")]))

		#expect(changes.added.map(\.id) == ["4"])
		#expect(changes.changed.map(\.id) == ["2"])
		#expect(changes.removed == ["1"])
		#expect(set.networks.map(\.id) == ["2", "3", "4"])
	}

	@Test("An identical listing changes nothing but still names the listing")
	func identicalSnapshot() {
		var set = BouncerNetworkSet()
		_ = set.apply(.snapshot([network("1", "A")]))

		let changes = set.apply(.snapshot([network("1", "A")]))

		#expect(changes.isEmpty)
		#expect(changes.completeListing == ["1"])
	}

	@Test("A network listed twice keeps its last description and its first place")
	func duplicateIdentifiersCollapse() {
		var set = BouncerNetworkSet()

		_ = set.apply(.snapshot([network("1", "first"), network("2", "B"), network("1", "last")]))

		#expect(set.networks.map(\.id) == ["1", "2"])
		#expect(set.network(withIdentifier: "1")?.name == "last")
	}

	@Test("A notification adds, changes and removes one network")
	func notifications() {
		var set = BouncerNetworkSet()

		#expect(set.apply(.upsert(network("1", "A"))).added.map(\.id) == ["1"])
		#expect(set.apply(.upsert(network("1", "A"))).isEmpty)
		#expect(set.apply(.upsert(network("1", "A", state: .connected))).changed.map(\.id) == ["1"])
		#expect(set.apply(.remove("1")).removed == ["1"])
		#expect(set.apply(.remove("1")).isEmpty)
		#expect(set.networks.isEmpty)
	}

	@Test("A partial update merges into the network and keeps what it does not name")
	func partialUpdateMerges() throws {
		var set = BouncerNetworkSet()
		var full = network("1", "Libera", state: .connecting)
		full.host = "irc.libera.chat"
		_ = set.apply(.snapshot([full]))

		let changes = set.apply(.update("1", ["state": "connected"]))

		#expect(changes.changed.map(\.id) == ["1"])
		let merged = try #require(set.network(withIdentifier: "1"))
		#expect(merged.state == .connected)
		#expect(merged.name == "Libera")
		#expect(merged.host == "irc.libera.chat")
	}

	@Test("An empty value removes the attribute, and a repeated update changes nothing")
	func emptyValueRemoves() {
		var set = BouncerNetworkSet()
		var full = network("1", "Libera", state: .disconnected)
		full.error = "Connection refused"
		_ = set.apply(.snapshot([full]))

		#expect(set.apply(.update("1", ["error": ""])).changed.map(\.id) == ["1"])
		#expect(set.network(withIdentifier: "1")?.error == nil)
		#expect(set.network(withIdentifier: "1")?.name == "Libera")
		#expect(set.apply(.update("1", ["error": ""])).isEmpty)
	}

	@Test("An update for a network not known yet adds it from what the update says")
	func updateOfUnknownNetworkAdds() {
		var set = BouncerNetworkSet()

		let changes = set.apply(.update("9", ["name": "New", "host": "irc.example.net"]))

		#expect(changes.added.map(\.id) == ["9"])
		#expect(changes.completeListing == nil)
		#expect(set.network(withIdentifier: "9")?.host == "irc.example.net")
		#expect(set.apply(.update("10", ["state": "connecting"])).added.map(\.id) == ["10"])
		#expect(set.network(withIdentifier: "10")?.displayName == "10")
	}

	@Test("Updates past the network limit are ignored")
	func updatesAreBounded() {
		var set = BouncerNetworkSet()
		_ = set.apply(.snapshot((0 ..< BouncerNetworkAttributes.maximumNetworks).map { network(String($0), "N") }))

		#expect(set.apply(.update("extra", ["name": "X"])).isEmpty)
	}

	@Test("A notification never carries a complete listing")
	func notificationsAreNotListings() {
		var set = BouncerNetworkSet()

		#expect(set.apply(.upsert(network("1", "A"))).completeListing == nil)
		#expect(set.apply(.remove("1")).completeListing == nil)
	}

	@Test("A bouncer that names more networks than the limit has the surplus ignored")
	func networkCountIsBounded() {
		let limit = BouncerNetworkAttributes.maximumNetworks
		let listing = (0 ..< limit + 10).map { network(String($0), "N\($0)") }
		var set = BouncerNetworkSet()

		let changes = set.apply(.snapshot(listing))

		#expect(set.networks.count == limit)
		#expect(changes.added.count == limit)
		#expect(set.apply(.upsert(network("extra", "Extra"))).isEmpty)
		#expect(set.network(withIdentifier: "extra") == nil)
		#expect(set.apply(.upsert(network("0", "Renamed"))).changed.map(\.id) == ["0"])
	}
}
