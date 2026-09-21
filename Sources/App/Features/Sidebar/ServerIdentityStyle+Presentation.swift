// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

extension ServerIdentityStyle.Color {
	var nsColor: NSColor {
		switch self {
		case .standard: .secondaryLabelColor
		case .blue: .systemBlue
		case .teal: .systemTeal
		case .green: .systemGreen
		case .yellow: .systemYellow
		case .orange: .systemOrange
		case .red: .systemRed
		case .pink: .systemPink
		case .purple: .systemPurple
		}
	}

	var title: String {
		switch self {
		case .standard: String(localized: .ServerIdentity.defaultColor)
		case .blue: String(localized: .ServerIdentity.colorBlue)
		case .teal: String(localized: .ServerIdentity.colorTeal)
		case .green: String(localized: .ServerIdentity.colorGreen)
		case .yellow: String(localized: .ServerIdentity.colorYellow)
		case .orange: String(localized: .ServerIdentity.colorOrange)
		case .red: String(localized: .ServerIdentity.colorRed)
		case .pink: String(localized: .ServerIdentity.colorPink)
		case .purple: String(localized: .ServerIdentity.colorPurple)
		}
	}
}

extension ServerIdentityStyle.Icon {
	var symbolName: String {
		switch self {
		case .network: "network"
		case .globe: "globe"
		case .chat: "bubble.left.and.bubble.right.fill"
		case .terminal: "terminal.fill"
		case .code: "chevron.left.forwardslash.chevron.right"
		case .people: "person.3.fill"
		case .game: "gamecontroller.fill"
		case .bolt: "bolt.fill"
		case .leaf: "leaf.fill"
		case .star: "star.fill"
		case .heart: "heart.fill"
		case .server: "server.rack"
		}
	}

	var title: String {
		switch self {
		case .network: String(localized: .ServerIdentity.iconNetwork)
		case .globe: String(localized: .ServerIdentity.iconGlobe)
		case .chat: String(localized: .ServerIdentity.iconChat)
		case .terminal: String(localized: .ServerIdentity.iconTerminal)
		case .code: String(localized: .ServerIdentity.iconCode)
		case .people: String(localized: .ServerIdentity.iconPeople)
		case .game: String(localized: .ServerIdentity.iconGame)
		case .bolt: String(localized: .ServerIdentity.iconBolt)
		case .leaf: String(localized: .ServerIdentity.iconLeaf)
		case .star: String(localized: .ServerIdentity.iconStar)
		case .heart: String(localized: .ServerIdentity.iconHeart)
		case .server: String(localized: .ServerIdentity.iconServer)
		}
	}
}
