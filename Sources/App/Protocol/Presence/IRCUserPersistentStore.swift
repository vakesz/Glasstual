/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

final nonisolated class UserPersistentStore {
	var relations: UserRelations?
	var presentAwayMessageFor301LastEvent: CFAbsoluteTime = 0
	var removeUserTimer: (any DispatchSourceTimer)?

	/** The store is shared by a user and every copy of it, so the removal timer belongs
	 to the store's lifetime. Cancelling it from `User.deinit` meant a throwaway mutable
	 copy retired the live user's timer and users were never reaped. */
	deinit {
		removeUserTimer?.cancel()
	}
}
