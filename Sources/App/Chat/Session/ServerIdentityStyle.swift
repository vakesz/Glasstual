// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// The identity a reader assigns to a connection. Stored names describe the
/// choice; platform colors and symbol names belong to the sidebar adapter.
nonisolated struct ServerIdentityStyle: Codable, Equatable, Sendable {
	enum Color: String, Codable, CaseIterable, Sendable {
		case standard, blue, teal, green, yellow, orange, red, pink, purple
	}

	enum Icon: String, Codable, CaseIterable, Sendable {
		case network, globe, chat, terminal, code, people, game, bolt, leaf, star, heart, server
	}

	var color: Color = .standard
	var icon: Icon = .network
}
