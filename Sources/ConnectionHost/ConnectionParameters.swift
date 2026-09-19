// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Network
import Security

/** The Network.framework parameters a configuration asks for.

 Everything here is a pure function of `ConnectionConfig`: which IP versions to
 dial, which protocol versions and cipher suites the handshake offers, which
 identity it presents, and which proxy the parameters route through. None of it
 needs the socket, so none of it is on the actor that owns one. */
nonisolated enum ConnectionParameters {
	private static let torProxyAddress = "127.0.0.1"
	private static let torProxyPort: UInt16 = 9150

	/// Where the connection actually dials, when it is not the server itself.
	static func proxyEndpoint(for config: ConnectionConfig) -> (host: String, port: UInt16)? {
		switch config.proxyType {
		case .socks5, .HTTP:
			guard let host = config.proxyAddress, host.isEmpty == false else {
				return nil
			}

			return (host: host, port: config.proxyPort)
		case .tor:
			return (host: torProxyAddress, port: torProxyPort)
		case .none, .automatic:
			return nil
		@unknown default:
			return nil
		}
	}

	static func tcp(for config: ConnectionConfig) -> TCP {
		switch config.addressType {
		case .v4:
			TCP { IP().version(.v4) }
		case .v6:
			TCP { IP().version(.v6) }
		default:
			TCP()
		}
	}

	/** The handshake as configured, without its certificate validator: who the
	 peer has to be is the socket's question, not the configuration's.

	 `offeringLegacyCipherSuites` is the transport's own second attempt, never a
	 setting: it adds the suites with no forward secrecy *after* the selected
	 ones, so a server that has anything better still picks it. Everything else
	 about the handshake -- the minimum protocol version, the client identity,
	 the certificate validation the socket adds -- is the same on both dials. */
	static func tls(for config: ConnectionConfig, offeringLegacyCipherSuites: Bool) -> TLS {
		var tls = TLS { tcp(for: config) }
			.version(min: SecureTransportSupport.minimumProtocolType)

		if let identity = clientIdentity(for: config) {
			tls = tls.localIdentity(identity)
		}

		let selected = SecureTransportSupport.cipherSuites(inCollection: config.cipherSuites)

		if selected.isEmpty {
			tls = tls.cipherSuiteGroups([.default])
		} else {
			tls = tls.cipherSuites(suiteValues(selected))
		}

		if offeringLegacyCipherSuites {
			tls = tls.cipherSuites(suiteValues(SecureTransportSupport.legacyCipherSuites))
		}

		return tls
	}

	/// The suites the framework negotiates from. A raw value outside
	/// `tls_ciphersuite_t` is not a weaker choice but no choice at all, which is
	/// why `SecureTransportTests` pins every list against the enum.
	private static func suiteValues(_ suites: [NSNumber]) -> [tls_ciphersuite_t] {
		suites.compactMap { tls_ciphersuite_t(rawValue: $0.uint16Value) }
	}

	static func applyProxy(
		_ config: ConnectionConfig,
		to parameters: NWParameters,
		uniqueIdentifier: String
	) throws {
		switch config.proxyType {
		case .none:
			parameters.preferNoProxies = true
		case .automatic:
			/* The default privacy context consults the system proxy settings
			 (including PAC) so there is nothing to configure. */
			parameters.preferNoProxies = false
		case .socks5, .HTTP, .tor:
			guard let endpoint = proxyEndpoint(for: config) else {
				throw ConnectionError.other(message: String(localized: .ConnectionErrors.proxyAddressMissing))
			}

			let nwEndpoint = NWEndpoint.hostPort(
				host: NWEndpoint.Host(endpoint.host),
				port: NWEndpoint.Port(integerLiteral: endpoint.port)
			)

			var proxyConfiguration = if config.proxyType == .HTTP {
				ProxyConfiguration(httpCONNECTProxy: nwEndpoint)
			} else {
				ProxyConfiguration(socksv5Proxy: nwEndpoint)
			}

			/* A proxy the user asked for must be used; never fall back to a
			 direct connection. */
			proxyConfiguration.allowFailover = false

			if config.proxyType != .tor,
			   let username = config.proxyUsername, username.isEmpty == false,
			   let password = config.proxyPassword, password.isEmpty == false
			{
				proxyConfiguration.applyCredential(username: username, password: password)
			}

			let privacyContext = NWParameters.PrivacyContext(description: "Glasstual.IRCConnection.\(uniqueIdentifier)")

			privacyContext.proxyConfigurations = [proxyConfiguration]

			parameters.setPrivacyContext(privacyContext)

			parameters.preferNoProxies = false
		@unknown default:
			throw ConnectionError.other(message: String(localized: .ConnectionErrors.unsupportedProxyType))
		}
	}

	/** The client-side identity this connection presents, when one is configured.

	 A pure function of the configuration — the keychain lookup depends on
	 nothing else — so it is done where the handshake needs it rather than
	 cached on an object. */
	private static func clientIdentity(for config: ConnectionConfig) -> sec_identity_t? {
		guard let certificateData = config.identityClientSideCertificate else {
			return nil
		}

		var certificateObject: CFTypeRef?

		var status = SecItemCopyMatching(
			[
				kSecClass: kSecClassCertificate,
				kSecValuePersistentRef: certificateData,
				kSecReturnRef: true,
			] as CFDictionary, &certificateObject
		)

		if status != errSecSuccess {
			ConnectionHostLog.connection.error("Client certificate lookup failed: \(status, privacy: .public)")

			return nil
		}

		guard let certificateObject,
		      CFGetTypeID(certificateObject) == SecCertificateGetTypeID()
		else {
			return nil
		}
		// Security exposes the typed certificate through a CFTypeRef result.
		let certificate = unsafeDowncast(certificateObject, to: SecCertificate.self)

		var identity: SecIdentity?

		status = SecIdentityCreateWithCertificate(nil, certificate, &identity)

		guard status == noErr, let identity else {
			ConnectionHostLog.connection.error("Client identity lookup failed: \(status, privacy: .public)")

			return nil
		}

		return sec_identity_create_with_certificates(identity, [certificate] as CFArray)
	}
}
