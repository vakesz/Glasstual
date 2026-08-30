/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

enum HighlightMatchBehavior: CaseIterable, Hashable, Identifiable, Sendable {
	case include
	case exclude

	init(excludesMatches: Bool) {
		self = excludesMatches ? .exclude : .include
	}

	var id: Self {
		self
	}

	var excludesMatches: Bool {
		self == .exclude
	}
}

struct HighlightEntryChannel: Equatable, Hashable, Identifiable, Sendable {
	let id: String
	let name: String
}

enum HighlightChannelSelection: Equatable, Hashable, Sendable {
	case all
	case channel(id: String)

	var channelID: String? {
		switch self {
		case .all:
			nil
		case let .channel(id):
			id
		}
	}
}
