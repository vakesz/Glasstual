// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// The Known Certificates sheet lists, searches and prunes what the stores
/// hold, and never creates an identity just by listing it.
@Suite("Known certificates")
@MainActor
struct DCCKnownCertificatesModelTests {
	private let identities = DCCLocalIdentityStore(storage: InMemoryDCCIdentityStorage())
	private let pins = DCCPeerCertificateStore(fileURL: nil)
	private let networks = [
		DCCKnownCertificatesModel.Network(id: "net-a", name: "Alpha"),
		DCCKnownCertificatesModel.Network(id: "net-b", name: "Beta"),
	]

	private func model() -> DCCKnownCertificatesModel {
		DCCKnownCertificatesModel(networks: networks, identities: identities, pins: pins)
	}

	private func pin(_ nickname: String, on network: String) async throws {
		let certificate = try #require(DCCPeerCertificate(der: PeerCertificateFixture.ellipticCurve()))
		try await pins.remember(certificate, network: network, nickname: nickname, caseMapping: .rfc1459, account: nil, at: .now)
	}

	@Test("Listing shows existing identities only and creates none")
	func listingCreatesNoIdentity() async throws {
		let existing = try await identities.identity(forNetwork: "net-a")
		let model = model()

		await model.load()

		#expect(model.own.map(\.fingerprint) == [existing.fingerprint, nil])
		#expect(try await identities.existingIdentity(forNetwork: "net-b") == nil)
	}

	@Test("Trusted certificates are listed by network name and can be searched")
	func trustedAreListedAndSearched() async throws {
		try await pin("carol", on: "net-b")
		try await pin("alice", on: "net-a")
		let model = model()

		await model.load()

		#expect(model.trusted.map(\.nickname) == ["alice", "carol"])
		#expect(model.trusted.map(\.networkName) == ["Alpha", "Beta"])
		model.searchText = "bet"
		#expect(model.visibleTrusted.map(\.nickname) == ["carol"])
	}

	@Test("Removing the selection removes only those pins")
	func removeSelection() async throws {
		try await pin("alice", on: "net-a")
		try await pin("bob", on: "net-a")
		let model = model()
		await model.load()

		model.selection = Set(model.trusted.filter { $0.nickname == "alice" }.map(\.id))
		await model.removeSelected()

		#expect(model.trusted.map(\.nickname) == ["bob"])
		#expect(model.selection.isEmpty)
	}

	@Test("Remove All empties every network")
	func removeAll() async throws {
		try await pin("alice", on: "net-a")
		try await pin("carol", on: "net-b")
		let model = model()
		await model.load()

		await model.removeAll()

		#expect(model.trusted.isEmpty)
		#expect(await pins.all().isEmpty)
	}

	@Test("Creating a new certificate changes the network's fingerprint")
	func replaceOwnCertificate() async throws {
		let old = try await identities.identity(forNetwork: "net-a")
		let model = model()
		await model.load()
		let own = try #require(model.own.first)

		await model.replaceCertificate(of: own)

		let replaced = try #require(model.own.first?.fingerprint)
		#expect(replaced != old.fingerprint)
	}
}
