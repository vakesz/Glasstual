// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("Connection configuration from a server configuration")
struct ConnectionConfigServerConfigTests {
	private func proxiedConfig(_ kind: ConnectionProxyKind) -> ServerConfig {
		var config = ServerConfig()
		config.proxyType = kind
		config.proxyAddress = "proxy.example"
		config.proxyPort = 9050
		config.proxyUsername = "user"
		return config
	}

	@Test("A SOCKS5 or HTTP proxy is copied with its address", arguments: [ConnectionProxyKind.socks5, .HTTP])
	func addressedProxyIsCopied(_ kind: ConnectionProxyKind) {
		var socketConfig = ConnectionConfig()

		socketConfig.apply(proxiedConfig(kind), bypassProxy: false)

		#expect(socketConfig.proxyType == kind)
		#expect(socketConfig.proxyAddress == "proxy.example")
		#expect(socketConfig.proxyPort == 9050)
		#expect(socketConfig.proxyUsername == "user")
	}

	@Test("Tor and the system proxy copy only the kind", arguments: [ConnectionProxyKind.tor, .automatic])
	func unaddressedProxyCopiesOnlyTheKind(_ kind: ConnectionProxyKind) {
		var socketConfig = ConnectionConfig()

		socketConfig.apply(proxiedConfig(kind), bypassProxy: false)

		#expect(socketConfig.proxyType == kind)
		#expect(socketConfig.proxyAddress == nil)
		#expect(socketConfig.proxyPort == ConnectionDefaults.proxyPort)
		#expect(socketConfig.proxyUsername == nil)
	}

	@Test("Bypassing the proxy leaves it unset")
	func bypassLeavesProxyUnset() {
		var socketConfig = ConnectionConfig()

		socketConfig.apply(proxiedConfig(.socks5), bypassProxy: true)

		#expect(socketConfig.proxyType == .none)
		#expect(socketConfig.proxyAddress == nil)
		#expect(socketConfig.proxyUsername == nil)
	}

	@Test("An endpoint that requires a trusted certificate validates the chain")
	func trustedCertificateForcesValidation() {
		var config = ServerConfig()
		config.validateServerCertificateChain = false
		var plain = ConnectionConfig()
		var required = ConnectionConfig()
		required.connectionRequiresTrustedCertificate = true

		plain.apply(config, bypassProxy: false)
		required.apply(config, bypassProxy: false)

		#expect(plain.connectionShouldValidateCertificateChain == false)
		#expect(required.connectionShouldValidateCertificateChain)
	}
}
