/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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

nonisolated let TPCPreferencesDictionaryVersion: UInt = 602 // nonisolated: let

public enum TXNicknameHighlightMatchType: UInt, Sendable {
	case partial
	case exact
	case regularExpression
}

public enum TXTabKeyAction: UInt, Sendable {
	case nicknameComplete = 0
	case unreadChannel = 1
	case none = 100
}

public enum TXUserDoubleClickAction: UInt, Sendable {
	case whois = 100
	case privateMessage = 200
	case insertTextField = 300
}

public enum TXNoticeSendLocation: UInt, Sendable {
	case serverConsole
	case selectedChannel
	case query
}

public enum TXCommandWKeyAction: UInt, Sendable {
	case closeWindow
	case partChannel
	case disconnect
	case terminate
}

public enum TXHostmaskBanFormat: UInt, Sendable {
	case whnin
	case whainn
	case whanni
	case exact
}

public enum TVCMainWindowTextViewFontSize: UInt, Sendable {
	case normal = 1
	case large
	case extraLarge
	case humongous
}

public enum TXFileTransferRequestReply: UInt, Sendable {
	case ignore = 1
	case openDialog
	case automaticallyDownload
}

public enum TXFileTransferIPAddressMethodDetection: UInt, Sendable {
	// Raw values preserve existing preferences.
	case routerOnly = 3
	case routerAndFirstParty = 1
	case routerAndThirdParty = 4
	case manual = 2
}

public enum TXPreferredAppearance: UInt, Sendable {
	case inherited
	case light
	case dark
}

/* Every one of these is stored as the integer it declares, so the typed store
 reads and writes them directly. A stored value with no matching case decodes to
 nothing and the read falls back to the key's declared default, which is what
 the hand-written `?? .someCase` at each call site used to do. */
extension TXNicknameHighlightMatchType: PreferenceEnum {}
extension TXTabKeyAction: PreferenceEnum {}
extension TXUserDoubleClickAction: PreferenceEnum {}
extension TXNoticeSendLocation: PreferenceEnum {}
extension TXCommandWKeyAction: PreferenceEnum {}
extension TXHostmaskBanFormat: PreferenceEnum {}
extension TVCMainWindowTextViewFontSize: PreferenceEnum {}
extension TXFileTransferRequestReply: PreferenceEnum {}
extension TXFileTransferIPAddressMethodDetection: PreferenceEnum {}
extension TXPreferredAppearance: PreferenceEnum {}
