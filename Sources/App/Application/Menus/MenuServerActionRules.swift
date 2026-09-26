// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

struct MenuServerActionRules {
	let canConnect: Bool
	let canConnectWithoutProxy: Bool
	let canDisconnect: Bool
	let canCancelReconnect: Bool

	init(session: ServerSession?) {
		let connected = session.map { $0.isConnecting || $0.isConnected } == true
		let available = session.map { !$0.isQuitting && !$0.isDisconnecting && !$0.isTerminating } == true
		canConnect = available && connected == false
		canConnectWithoutProxy = canConnect && session.map { $0.config.proxyType != .none } == true
		canDisconnect = available && connected
		canCancelReconnect = available && session?.isReconnecting == true
	}
}
