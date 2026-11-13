// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Application-wide state the protocol layer branches on. A separate seam from
 the window so that a session can be built without one. */
@MainActor
protocol ApplicationStatePresenting: AnyObject {
	var ghostModeIsOn: Bool { get }
	var applicationIsTerminating: Bool { get }
	/// Decremented by each session as it finishes its termination work.
	func noteSessionDidFinishTerminating()
}
