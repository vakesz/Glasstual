// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import CryptoKit
import Foundation
import Security

/** The key and self-signed certificate this user presents on secure DCC
 connections made from one network.

 Both halves are plain bytes so the identity can cross isolation boundaries.
 The `SecIdentity` TLS needs is built from them by ``makeSecIdentity()`` inside
 whichever actor owns the connection, because neither it nor `sec_identity_t`
 is `Sendable`. */
nonisolated struct DCCLocalIdentity: Equatable, Sendable {
	enum IdentityError: Error, Equatable {
		case unreadableKey
		case unreadableCertificate
		/// The certificate certifies some other key.
		case mismatchedCertificate
		/// Security refused to pair the certificate with the key.
		case identityUnavailable
		/// The stored pair exists, or may exist, but could not be read.
		case unreadableStorage
	}

	/// How long a new certificate is valid. Peers pin the fingerprint rather
	/// than checking dates, so the period only has to outlast the identity.
	static let validityPeriod: TimeInterval = 10 * 365 * 24 * 60 * 60
	/// How far a new certificate's validity reaches into the past, so a peer
	/// whose clock is a little behind does not see one from the future.
	static let backdating: TimeInterval = 24 * 60 * 60

	/// The private key's X9.63 representation.
	let privateKey: Data
	/// The certificate's DER encoding.
	let certificate: Data
	let fingerprint: DCCCertificateFingerprint

	/// Pairs a stored key and certificate, refusing a pair that does not
	/// belong together.
	init(privateKey: Data, certificate: Data) throws {
		guard let key = try? P256.Signing.PrivateKey(x963Representation: privateKey) else {
			throw IdentityError.unreadableKey
		}
		guard let parsed = SecCertificateCreateWithData(nil, certificate as CFData) else {
			throw IdentityError.unreadableCertificate
		}
		guard let certifiedKey = SecCertificateCopyKey(parsed),
		      let certifiedBytes = SecKeyCopyExternalRepresentation(certifiedKey, nil) as Data?,
		      certifiedBytes == key.publicKey.x963Representation
		else {
			throw IdentityError.mismatchedCertificate
		}

		self.privateKey = privateKey
		self.certificate = certificate
		fingerprint = DCCCertificateFingerprint(certificate: certificate)
	}

	/// A new key and a certificate for it, valid from a day ago for ten years.
	static func generate(now: Date = .now) throws -> DCCLocalIdentity {
		let key = P256.Signing.PrivateKey()
		let certificate = try DCCSelfSignedCertificate.make(
			privateKey: key,
			serialNumber: DCCSelfSignedCertificate.randomSerialNumber(),
			notBefore: now.addingTimeInterval(-backdating),
			notAfter: now.addingTimeInterval(validityPeriod)
		)
		return try DCCLocalIdentity(privateKey: key.x963Representation, certificate: certificate)
	}

	/// The identity in the form Network.framework presents. Call it from the
	/// actor that will own the connection.
	func makeSecIdentity() throws -> sec_identity_t {
		let attributes: [CFString: Any] = [
			kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
			kSecAttrKeyClass: kSecAttrKeyClassPrivate,
		]
		guard let key = SecKeyCreateWithData(privateKey as CFData, attributes as CFDictionary, nil) else {
			throw IdentityError.unreadableKey
		}
		guard let parsed = SecCertificateCreateWithData(nil, certificate as CFData) else {
			throw IdentityError.unreadableCertificate
		}
		guard let identity = SecIdentityCreate(nil, parsed, key), let wrapped = sec_identity_create(identity) else {
			throw IdentityError.identityUnavailable
		}
		return wrapped
	}
}

/// Where local DCC identities are kept. The keychain in the app, memory in
/// tests.
nonisolated protocol DCCIdentityStorage: Sendable {
	/// What is stored for the network. Only a pair confirmed missing is
	/// ``DCCStoredIdentity/absent``; a failed read says so instead.
	func read(network: String) -> DCCStoredIdentity
	func save(privateKey: Data, certificate: Data, network: String) throws
	func remove(network: String)
}

/// What a storage holds for one network.
nonisolated enum DCCStoredIdentity: Equatable, Sendable {
	/// Neither item exists.
	case absent
	case present(privateKey: Data, certificate: Data)
	/// A half pair, undecodable data or a keychain error: something may be
	/// stored, and it must not be overwritten.
	case unreadable
}

/** The keychain items behind a network's identity: the key and the
 certificate, each base64 in a generic-password item in the app's access
 group, readable only on this device after first unlock.

 They are not settings, so settings export never carries them, and they are
 not copied when a server configuration is duplicated. */
nonisolated struct KeychainDCCIdentityStorage: DCCIdentityStorage {
	func read(network: String) -> DCCStoredIdentity {
		Self.combine(
			key: KeychainItem.dccIdentityKey(network).passwordRead,
			certificate: KeychainItem.dccIdentityCertificate(network).passwordRead
		)
	}

	/// Both items absent is absent; both present and base64 is present;
	/// anything else, including one item without the other, is unreadable.
	static func combine(key: KeychainReadResult, certificate: KeychainReadResult) -> DCCStoredIdentity {
		switch (key, certificate) {
		case (.absent, .absent):
			.absent
		case let (.present(keyText), .present(certificateText)):
			if let keyData = Data(base64Encoded: keyText), let certificateData = Data(base64Encoded: certificateText) {
				.present(privateKey: keyData, certificate: certificateData)
			} else {
				.unreadable
			}
		default:
			.unreadable
		}
	}

	func save(privateKey: Data, certificate: Data, network: String) throws {
		try KeychainItem.dccIdentityKey(network).apply(.set(privateKey.base64EncodedString())).get()
		try KeychainItem.dccIdentityCertificate(network).apply(.set(certificate.base64EncodedString())).get()
	}

	func remove(network: String) {
		KeychainItem.dccIdentityKey(network).apply(.cleared)
		KeychainItem.dccIdentityCertificate(network).apply(.cleared)
	}
}

/** Creates, keeps and discards the local identity of each network.

 The actor serialises the read-then-create step, so two secure connections
 starting together on a network that has no identity yet agree on one instead
 of each writing its own. Keychain calls block, which is why they run here
 rather than on the main actor. */
actor DCCLocalIdentityStore {
	private let storage: any DCCIdentityStorage
	private let now: @Sendable () -> Date

	init(storage: any DCCIdentityStorage, now: @escaping @Sendable () -> Date = { .now }) {
		self.storage = storage
		self.now = now
	}

	/// The network's identity, created and stored the first time it is asked
	/// for.
	///
	/// A stored pair that cannot be read, for any reason, is an error rather
	/// than a reason to make a new one: peers may have pinned it, so replacing it is the
	/// user's decision, made through ``regenerate(forNetwork:)``.
	func identity(forNetwork network: String) throws -> DCCLocalIdentity {
		switch storage.read(network: network) {
		case let .present(privateKey, certificate):
			return try DCCLocalIdentity(privateKey: privateKey, certificate: certificate)
		case .absent:
			return try create(forNetwork: network)
		case .unreadable:
			throw DCCLocalIdentity.IdentityError.unreadableStorage
		}
	}

	/// The network's identity if one was ever created, without creating one.
	func existingIdentity(forNetwork network: String) throws -> DCCLocalIdentity? {
		switch storage.read(network: network) {
		case let .present(privateKey, certificate):
			return try DCCLocalIdentity(privateKey: privateKey, certificate: certificate)
		case .absent:
			return nil
		case .unreadable:
			throw DCCLocalIdentity.IdentityError.unreadableStorage
		}
	}

	/// Replaces the network's identity with a new one. Peers that pinned the
	/// old certificate will see a change.
	func regenerate(forNetwork network: String) throws -> DCCLocalIdentity {
		try create(forNetwork: network)
	}

	func remove(forNetwork network: String) {
		storage.remove(network: network)
	}

	private func create(forNetwork network: String) throws -> DCCLocalIdentity {
		let identity = try DCCLocalIdentity.generate(now: now())
		do {
			try storage.save(privateKey: identity.privateKey, certificate: identity.certificate, network: network)
		} catch {
			/* Half a pair is worse than none: the next request would refuse it as
			 unreadable instead of creating a complete one. */
			storage.remove(network: network)
			DirectConnectionLog.transport.error("Could not store a secure DCC identity: \(error.localizedDescription, privacy: .public)")
			throw error
		}
		return identity
	}
}

nonisolated extension ServerConfig {
	/// The keychain items holding this network's secure DCC identity. They are
	/// filed under the network's own identifier, bouncer networks included, so
	/// no two networks share a certificate a peer could link them by.
	var dccIdentityKeychainItems: [KeychainItem] {
		[.dccIdentityKey(uniqueIdentifier), .dccIdentityCertificate(uniqueIdentifier)]
	}
}
