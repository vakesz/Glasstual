// Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// When a channel mode carries a parameter on the wire.
nonisolated enum ModeParameterPolicy: Sendable, Equatable {
	case always
	case onlyWhenSet
	case never

	func requiresParameter(whenModeIsSet modeIsSet: Bool) -> Bool {
		switch self {
		case .always:
			true
		case .onlyWhenSet:
			modeIsSet
		case .never:
			false
		}
	}
}

/// The class a channel mode belongs to.
///
/// ISUPPORT `CHANMODES` lists four comma-separated groups in a fixed order and
/// the group decides whether the mode takes a parameter; `PREFIX` adds a fifth
/// kind of its own. The parser used to store the group as its one-based index
/// with 100 standing in for a prefix mode, and every reader had to know that
/// 1, 2 and 100 mean "parameterised", 3 means "only when set" and 4 means
/// "never".
nonisolated enum ChannelModeKind: Sendable, Equatable, CaseIterable {
	/// CHANMODES group A: a list mode such as `b`, always parameterised.
	case list
	/// Group B: a setting that is parameterised in both directions, like `k`.
	case setting
	/// Group C: a setting parameterised only when it is set, like `l`.
	case settingWhenSet
	/// Group D: a plain flag such as `t`, never parameterised.
	case flag
	/// A mode advertised through `PREFIX`, parameterised by the nickname it
	/// applies to.
	case userPrefix

	/// The group at `index` in a `CHANMODES` token, or `nil` past group D.
	init?(chanModesGroupIndex index: Int) {
		switch index {
		case 0: self = .list
		case 1: self = .setting
		case 2: self = .settingWhenSet
		case 3: self = .flag
		default: return nil
		}
	}

	var parameterPolicy: ModeParameterPolicy {
		switch self {
		case .list, .setting, .userPrefix:
			.always
		case .settingWhenSet:
			.onlyWhenSet
		case .flag:
			.never
		}
	}
}
