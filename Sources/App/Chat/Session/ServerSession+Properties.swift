// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

extension ServerSession {
	var networkName: String? {
		supportInfo.networkNameFormatted
	}

	var networkNameAlt: String {
		networkName ?? config.connectionName
	}

	var serverAddress: String? {
		supportInfo.serverAddress ?? socket?.config.serverAddress ?? endpoints.current?.serverAddress
	}

	var isReconnecting: Bool {
		reconnect.timer.isActive
	}

	var isSecured: Bool {
		socket?.isSecured ?? false
	}

	var zncBouncerCertificateChainData: Data? {
		guard znc.isConnected,
		      znc.isSendingCertificateInfo == false,
		      let certificateData = znc.certificateChainText
		else { return nil }
		return certificateData.data(using: .ascii)
	}
}
