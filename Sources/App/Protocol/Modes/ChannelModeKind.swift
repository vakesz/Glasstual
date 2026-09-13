/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

/// When a channel mode carries a parameter on the wire.
public nonisolated enum ModeParameterPolicy: Sendable, Equatable { // nonisolated: value
	case always
	case onlyWhenSet
	case never

	public func requiresParameter(whenModeIsSet modeIsSet: Bool) -> Bool {
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
public nonisolated enum ChannelModeKind: Sendable, Equatable, CaseIterable { // nonisolated: value
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
	public init?(chanModesGroupIndex index: Int) {
		switch index {
		case 0: self = .list
		case 1: self = .setting
		case 2: self = .settingWhenSet
		case 3: self = .flag
		default: return nil
		}
	}

	public var parameterPolicy: ModeParameterPolicy {
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
