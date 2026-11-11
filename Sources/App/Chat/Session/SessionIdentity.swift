// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// Who the server says this connection is.
struct SessionIdentity {
	/// The nickname the server assigned, or `nil` before it has assigned one.
	var assignedNickname: String?
	/// The user's own `nick!user@host`, as the server last reported it.
	var hostmask: String?
	var isIRCop = false
	/// The services account the server last reported the session logged in to,
	/// or `nil` while it is not logged in.
	var account: String?
}
