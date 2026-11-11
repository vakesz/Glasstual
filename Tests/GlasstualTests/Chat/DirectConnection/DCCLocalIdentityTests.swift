// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import CryptoKit
import Foundation
@testable import Glasstual
import Security
import Synchronization
import Testing

/// Identity storage in memory, standing in for the keychain.
final nonisolated class InMemoryDCCIdentityStorage: DCCIdentityStorage { // nonisolated: guarded
	struct Failure: Error {}

	private let items = Mutex<[String: (privateKey: Data, certificate: Data)]>([:])
	private let failsSaves: Bool

	init(failsSaves: Bool = false) {
		self.failsSaves = failsSaves
	}

	func load(network: String) -> (privateKey: Data, certificate: Data)? {
		items.withLock { $0[network] }
	}

	func save(privateKey: Data, certificate: Data, network: String) throws {
		if failsSaves {
			throw Failure()
		}
		items.withLock { $0[network] = (privateKey, certificate) }
	}

	func remove(network: String) {
		_ = items.withLock { $0.removeValue(forKey: network) }
	}

	func replace(network: String, privateKey: Data, certificate: Data) {
		items.withLock { $0[network] = (privateKey, certificate) }
	}

	var networks: Set<String> {
		items.withLock { Set($0.keys) }
	}
}

@Suite("DCC local identity")
struct DCCLocalIdentityTests {
	@Test("A generated identity is valid for ten years from a day ago and builds a TLS identity")
	func generated() throws {
		let now = Date(timeIntervalSince1970: 1_800_000_000)
		let identity = try DCCLocalIdentity.generate(now: now)
		let certificate = try #require(SecCertificateCreateWithData(nil, identity.certificate as CFData))

		#expect(SecCertificateCopyNotValidBeforeDate(certificate) as Date? == now.addingTimeInterval(-86400))
		#expect(SecCertificateCopyNotValidAfterDate(certificate) as Date?
			== now.addingTimeInterval(DCCLocalIdentity.validityPeriod))
		#expect(identity.fingerprint == DCCCertificateFingerprint(certificate: identity.certificate))
		_ = try identity.makeSecIdentity()
	}

	@Test("A key and a certificate that do not belong together are refused")
	func mismatch() throws {
		let first = try DCCLocalIdentity.generate()
		let second = try DCCLocalIdentity.generate()

		#expect(throws: DCCLocalIdentity.IdentityError.mismatchedCertificate) {
			try DCCLocalIdentity(privateKey: first.privateKey, certificate: second.certificate)
		}
		#expect(throws: DCCLocalIdentity.IdentityError.unreadableKey) {
			try DCCLocalIdentity(privateKey: Data([1, 2, 3]), certificate: first.certificate)
		}
		#expect(throws: DCCLocalIdentity.IdentityError.unreadableCertificate) {
			try DCCLocalIdentity(privateKey: first.privateKey, certificate: Data([0x30, 0x00]))
		}
	}

	@Test("The store creates an identity once and hands back the same one afterwards")
	func createdOnce() async throws {
		let storage = InMemoryDCCIdentityStorage()
		let store = DCCLocalIdentityStore(storage: storage)

		let first = try await store.identity(forNetwork: "network-a")
		let again = try await store.identity(forNetwork: "network-a")
		let other = try await store.identity(forNetwork: "network-b")

		#expect(first == again)
		#expect(first.fingerprint != other.fingerprint)
		#expect(storage.networks == ["network-a", "network-b"])
	}

	@Test("Concurrent first requests agree on one identity")
	func concurrentFirstUse() async throws {
		let store = DCCLocalIdentityStore(storage: InMemoryDCCIdentityStorage())
		let fingerprints = try await withThrowingTaskGroup(of: DCCCertificateFingerprint.self) { group in
			for _ in 0 ..< 8 {
				group.addTask { try await store.identity(forNetwork: "network").fingerprint }
			}
			var collected = Set<DCCCertificateFingerprint>()
			for try await fingerprint in group {
				collected.insert(fingerprint)
			}
			return collected
		}
		#expect(fingerprints.count == 1)
	}

	@Test("Regenerating changes the fingerprint and removing deletes both halves")
	func regenerateAndRemove() async throws {
		let storage = InMemoryDCCIdentityStorage()
		let store = DCCLocalIdentityStore(storage: storage)

		let original = try await store.identity(forNetwork: "network")
		let replacement = try await store.regenerate(forNetwork: "network")
		#expect(original.fingerprint != replacement.fingerprint)
		#expect(try await store.identity(forNetwork: "network") == replacement)

		await store.remove(forNetwork: "network")
		#expect(storage.load(network: "network") == nil)
	}

	@Test("A corrupt stored pair is an error and is not silently replaced")
	func corruptStoredPair() async throws {
		let storage = InMemoryDCCIdentityStorage()
		let good = try DCCLocalIdentity.generate()
		storage.replace(network: "network", privateKey: Data([9, 9, 9]), certificate: good.certificate)
		let store = DCCLocalIdentityStore(storage: storage)

		await #expect(throws: DCCLocalIdentity.IdentityError.unreadableKey) {
			try await store.identity(forNetwork: "network")
		}
		#expect(storage.load(network: "network")?.privateKey == Data([9, 9, 9]))
	}

	@Test("A failed save leaves nothing half-stored")
	func failedSave() async throws {
		let storage = InMemoryDCCIdentityStorage(failsSaves: true)
		let store = DCCLocalIdentityStore(storage: storage)

		await #expect(throws: InMemoryDCCIdentityStorage.Failure.self) {
			try await store.identity(forNetwork: "network")
		}
		#expect(storage.networks.isEmpty)
	}

	@Test("Identity items are per network and named apart from the other secrets")
	func keychainItems() {
		var config = ServerConfig(connectionName: "Identity fixture")
		config.uniqueIdentifier = "fixture-id"

		#expect(config.dccIdentityKeychainItems == [
			.dccIdentityKey("fixture-id"), .dccIdentityCertificate("fixture-id"),
		])
		#expect(KeychainItem.dccIdentityKey("x").service == "glasstual.dcc-identity-key.x")
		#expect(KeychainItem.dccIdentityCertificate("x").service == "glasstual.dcc-identity-certificate.x")
		#expect(config.keychainItems.contains(.dccIdentityKey("fixture-id")) == false)
	}
}
