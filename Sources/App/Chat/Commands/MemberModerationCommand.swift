// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The command lines the member commands raised from the member list and the
/// menus send. Nothing about them is a menu: the menu decides which one to
/// send, and the connection sends the text this builds.
nonisolated enum MemberModerationCommand {
	static func ignore(_ nickname: String) -> String {
		"ignore \(nickname)"
	}

	static func unignore(_ nickname: String) -> String {
		"unignore \(nickname)"
	}

	static func mode(_ command: String, nicknames: [String]) -> String {
		"\(command) \(nicknames.joined(separator: " "))"
	}

	static func kickban(_ nickname: String, reason: String) -> String {
		"KICKBAN \(nickname) \(reason)"
	}

	static func operatorCommand(_ command: String, nickname: String, reason: String) -> String {
		"\(command) \(nickname) \(reason)"
	}

	static func setVhost(_ vhost: String, nickname: String) -> String {
		"hs setall \(nickname) \(vhost)"
	}
}
