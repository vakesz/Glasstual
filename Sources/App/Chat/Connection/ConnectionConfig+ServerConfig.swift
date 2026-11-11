// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions

nonisolated extension ConnectionConfig {
	/// Copies what the session's configuration says about how to reach the server.
	mutating func apply(_ config: ServerConfig, bypassProxy: Bool) {
		addressType = config.addressType
		cipherSuites = config.cipherSuites
		connectionShouldValidateCertificateChain = config.validateServerCertificateChain
			|| connectionRequiresTrustedCertificate
		identityClientSideCertificate = config.identityClientSideCertificate
		if bypassProxy == false {
			proxyType = config.proxyType
			if proxyType == .socks5 || proxyType == .HTTP {
				proxyPort = config.proxyPort
				proxyAddress = config.proxyAddress
				proxyUsername = config.proxyUsername
			}
		}
		setFloodControl(
			delayInterval: config.floodControlDelayTimerInterval,
			maximumMessages: config.floodControlMaximumMessages
		)
	}
}
