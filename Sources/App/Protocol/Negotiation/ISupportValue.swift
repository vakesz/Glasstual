// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

enum ISupportListKind: UInt, Sendable {
	case ban = 0
	case banException = 1
	case inviteException = 2
	case quiet = 3
}

nonisolated enum ISupportCaseMapping: UInt, Sendable {
	case rfc1459 = 0
	case strictRFC1459 = 1
	case ascii = 2
	/// RFC 7613 §3.3 `UsernameCaseMapped`: Unicode case folding and NFC, with
	/// none of the ASCII bracket-to-brace equivalences the RFC 1459 mappings
	/// inherited from Scandinavian keyboards.
	case rfc7613 = 3
}

/// One token of an ISUPPORT line as the server sent it.
///
/// A token is either `KEY=value` or a bare `KEY` standing for a feature the
/// server merely announces. The most recent line is kept verbatim so the
/// numeric handler can spell it back out as the server sent it.
enum ISupportValue: Sendable, Equatable {
	case flag
	case text(String)
}
