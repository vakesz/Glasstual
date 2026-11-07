// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The menus the protocol layer raises. Kept apart from `ServerSessionPresenting` because
 the menu controller, not the window, owns them. */
@MainActor
protocol MenuPresenting: AnyObject {
	func toggleMuteOnNotificationSoundsShortcut(on muted: Bool)
	func showServerPropertiesSheet(for session: ServerSession, selection: ServerPropertiesDestination)
	func showNicknameColorSheet(forNickname nickname: String)
	func openAcknowledgements(_ sender: Any?)
	/// Selects the sidebar row a `glasstual://` link names.
	func navigate(to url: URL)
	/// Reveals a folder of the application's in the Finder. What "reveal" means
	/// is the app layer's business; the protocol layer only knows the folder.
	func revealInFinder(_ url: URL)
}
