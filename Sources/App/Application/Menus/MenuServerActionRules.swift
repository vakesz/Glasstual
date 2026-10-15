// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

struct MenuServerActionRules {
	let canConnect: Bool
	let canConnectWithoutProxy: Bool
	let canDisconnect: Bool
	let canCancelReconnect: Bool
	let canDeleteServer: Bool
	let isConnected: Bool

	init(session: ServerSession?) {
		let connected = session.map { $0.isConnecting || $0.isConnected } == true
		let available = session.map { !$0.isQuitting && !$0.isDisconnecting && !$0.isTerminating } == true
		isConnected = connected
		canConnect = available && connected == false
		canConnectWithoutProxy = canConnect && session.map { $0.config.proxyType != .none } == true
		canDisconnect = available && connected
		canCancelReconnect = available && session?.isReconnecting == true
		canDeleteServer = available && connected == false
	}
}

/// What ⌘W does, shared by the validator (title/enablement) and the action.
nonisolated enum CloseWindowBehavior { // nonisolated: pure
	case performClose
	case partConversation
	case disconnect
	case terminate

	static func resolve(
		action: CommandWShortcutAction,
		isKeyWindow: Bool,
		hasSession: Bool
	) -> CloseWindowBehavior? {
		if action == .closeWindow || isKeyWindow == false {
			return .performClose
		}
		guard hasSession else { return nil }
		return switch action {
		case .closeWindow: .performClose
		case .closeConversation: .partConversation
		case .disconnect: .disconnect
		case .terminate: .terminate
		}
	}
}
