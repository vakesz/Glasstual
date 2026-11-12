// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

extension ServerSession {
	var networkName: String? {
		supportInfo.networkNameFormatted
	}

	/** The name this connection is shown under, wherever it is named.

	 The reader named the connection, and that name is what the sidebar lists
	 it as, so every title, subtitle, menu and notification says the same. The
	 name the server announces stands in only for a connection without one. */
	var networkNameAlt: String {
		Self.displayName(connectionName: config.connectionName, announcedNetworkName: networkName)
	}

	nonisolated static func displayName( // nonisolated: pure
		connectionName: String,
		announcedNetworkName: String?
	) -> String {
		connectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			? announcedNetworkName ?? ""
			: connectionName
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
