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

/// The kind of IRC conversation represented by a channel model.
public enum ChannelType: UInt, CaseIterable, Sendable {
	case channel = 0
	case privateMessage = 1
	case utility = 2
	/// A DCC CHAT session. Direct chats are never persisted.
	case directChat = 3
}

/// The connection lifecycle state of an IRC channel.
public enum ChannelStatus: UInt, CaseIterable, Sendable {
	case parted = 0
	case joining = 1
	case joined = 2
	case terminated = 3
}

/// Membership privileges advertised by IRC channel prefix modes.
public struct UserRank: OptionSet, Hashable, Sendable {
	public let rawValue: UInt

	public init(rawValue: UInt) {
		self.rawValue = rawValue
	}

	/// No rank at all. An option set already spells that as the empty set, so
	/// `.none` no longer occupies a bit of its own and never has to be masked
	/// out of a union.
	public static let none = UserRank([])
	public static let irCopByMode = UserRank(rawValue: 1 << 1)
	public static let channelOwner = UserRank(rawValue: 1 << 2)
	public static let superOperator = UserRank(rawValue: 1 << 3)
	public static let normalOperator = UserRank(rawValue: 1 << 4)
	public static let halfOperator = UserRank(rawValue: 1 << 5)
	public static let voiced = UserRank(rawValue: 1 << 6)
}
