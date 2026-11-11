// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/// The credentials a connection could sign in with.
nonisolated struct SASLCredentialInventory: Sendable, Equatable {
	var hasClientCertificate = false
	var externalMechanismDisabled = false
	var hasPassword = false
	var hasSigningKey = false
	var hasBearerToken = false
}

/// How far the connection vouches for the server that would receive a credential.
nonisolated enum SASLTransportAssurance: Sendable, Equatable {
	/// An unencrypted socket. Credentials in clear are allowed only when
	/// nothing about the connection asked for encryption.
	case plaintext(clearCredentialsAllowed: Bool)
	/// TLS whose chain the system accepted, or that the user chose to continue
	/// with after being shown it failing.
	case verifiedTLS
	/// TLS whose chain nobody checked, because checking is off for the network.
	case unverifiedTLS(consented: Bool, mayAsk: Bool)
}

/// Whether a mechanism can be tried on this connection.
nonisolated enum SASLAvailability: Sendable, Equatable {
	case usable
	/// Usable once the user agrees to send the credential.
	case needsConsent
	case unavailable(SASLUnavailableReason)
}

/// Why a mechanism cannot be tried.
nonisolated enum SASLUnavailableReason: Sendable, Equatable {
	case noClientCertificate
	case externalDisabled
	case noSigningKey
	case noPassword
	case noBearerToken
	case clearTextNotPermitted
	/// The mechanism is only ever sent over TLS (RFC 7628 §5).
	case requiresTLS
	case accountCredentialsWithheld
}

/** What the session will speak for SASL, and how much of it.

 Pure decisions over the mechanisms and the payload: which mechanisms are on
 offer from this side, which one to try next, how long to wait for the server's
 half, and how the payload is cut into `AUTHENTICATE` lines. */
nonisolated enum SASLPolicy {
	/// Ceiling on the reassembled `AUTHENTICATE` payload. Every mechanism the
	/// session supports fits in a fraction of this; without it a server can
	/// grow the buffer 400 characters at a time forever.
	static let maximumPayloadLength = 16384

	/** Whether `mechanism` can be tried with these credentials over this transport.

	 A mechanism that sends the password as typed needs a connection that may
	 carry it, or the user's consent where it is only the certificate that was
	 not checked. Mechanisms that prove a credential without sending it are
	 usable on any transport. Nothing is usable once the connection went to a
	 host outside the network's configured servers. */
	static func availability(
		of mechanism: SASLMechanism,
		inventory: SASLCredentialInventory,
		transport: SASLTransportAssurance,
		withholdsAccountCredentials: Bool
	) -> SASLAvailability {
		guard withholdsAccountCredentials == false else {
			return .unavailable(.accountCredentialsWithheld)
		}

		switch mechanism.credential {
		case .clientCertificate:
			guard inventory.hasClientCertificate else { return .unavailable(.noClientCertificate) }
			return inventory.externalMechanismDisabled ? .unavailable(.externalDisabled) : .usable
		case .signingKey:
			return inventory.hasSigningKey ? .usable : .unavailable(.noSigningKey)
		case .passwordProof:
			return inventory.hasPassword ? .usable : .unavailable(.noPassword)
		case .passwordInClear:
			guard inventory.hasPassword else { return .unavailable(.noPassword) }
			return clearCredentialAvailability(over: transport)
		case .bearerToken:
			guard inventory.hasBearerToken else { return .unavailable(.noBearerToken) }
			/* RFC 7628 requires TLS whatever the endpoint asked for: a token on a
			 plaintext socket is a session anyone on the path can replay. */
			if case .plaintext = transport {
				return .unavailable(.requiresTLS)
			}
			return clearCredentialAvailability(over: transport)
		}
	}

	private static func clearCredentialAvailability(over transport: SASLTransportAssurance) -> SASLAvailability {
		switch transport {
		case let .plaintext(clearCredentialsAllowed):
			clearCredentialsAllowed ? .usable : .unavailable(.clearTextNotPermitted)
		case .verifiedTLS:
			.usable
		case let .unverifiedTLS(consented, mayAsk):
			if consented {
				.usable
			} else {
				mayAsk ? .needsConsent : .unavailable(.clearTextNotPermitted)
			}
		}
	}

	/** The mechanisms the session can speak, in the order it tries them.

	 Mechanisms waiting for consent stay in the list: the exchange holds the
	 credential until the user answers. A preference moves its mechanism to the
	 front and leaves the rest as the fallback, unless `onlyPreferred` is set,
	 in which case nothing else is tried. An unusable preference is ignored. */
	static func supportedMechanisms(
		inventory: SASLCredentialInventory,
		transport: SASLTransportAssurance,
		withholdsAccountCredentials: Bool,
		preferred: SASLMechanism?,
		onlyPreferred: Bool = false
	) -> [SASLMechanism] {
		var mechanisms = SASLMechanism.defaultOrder.filter { mechanism in
			let availability = availability(
				of: mechanism,
				inventory: inventory,
				transport: transport,
				withholdsAccountCredentials: withholdsAccountCredentials
			)
			if case .unavailable = availability {
				return false
			}
			return true
		}

		guard let preferred else {
			return mechanisms
		}

		guard let preferredIndex = mechanisms.firstIndex(of: preferred) else {
			return onlyPreferred ? [] : mechanisms
		}

		guard onlyPreferred == false else {
			return [preferred]
		}

		mechanisms.remove(at: preferredIndex)
		mechanisms.insert(preferred, at: 0)

		return mechanisms
	}

	/// The mechanisms named in a `sasl=` value or a 908 that the session
	/// speaks. Names it does not know are skipped, as sasl-3.2 requires.
	static func knownMechanisms(in offered: [String]) -> [SASLMechanism] {
		offered.compactMap(SASLMechanism.init(wireName:))
	}

	/** The first supported mechanism that was offered and has not been tried.

	 An empty offer is a `sasl` capability with no value, which says nothing
	 about the mechanisms, so every supported one counts as offered. */
	static func nextMechanism(
		from supported: [SASLMechanism],
		offered: [String],
		tried: [SASLMechanism]
	) -> SASLMechanism? {
		let known = Set(knownMechanisms(in: offered))

		return supported.first { mechanism in
			tried.contains(mechanism) == false && (offered.isEmpty || known.contains(mechanism))
		}
	}

	/// How long the session waits for the server's half of a SASL exchange.
	static let timeout: TimeInterval = 30

	static func wireChunks(for payload: String) -> [String] {
		wireChunks(for: Data(payload.utf8))
	}

	static func wireChunks(for payload: Data) -> [String] {
		let encoded = payload.base64EncodedString()

		guard encoded.isEmpty == false else {
			return ["+"]
		}

		var chunks: [String] = []
		var start = encoded.startIndex

		while start < encoded.endIndex {
			let end = encoded.index(start, offsetBy: 400, limitedBy: encoded.endIndex) ?? encoded.endIndex
			chunks.append(String(encoded[start ..< end]))
			start = end
		}

		if chunks.last?.count == 400 {
			chunks.append("+")
		}

		return chunks
	}
}
