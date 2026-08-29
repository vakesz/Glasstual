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

/** The state that belongs to a person rather than to one ``User`` value.

 A `User` is a value now, so a copy taken to be edited would copy this too. The
 client keeps one store per `User.ID` instead and hands it out by identity,
 which is what makes the removal timer and the away-message clock survive an
 edit -- and stops a throwaway copy from retiring the live user's timer, which
 is the bug the shared store was introduced to fix. */
@MainActor
final class UserPersistentStore {
	/// The channels the person is in. The member itself lives in each channel's
	/// member list; this records only where to look.
	var relations = UserRelations()

	var presentAwayMessageFor301LastEvent: CFAbsoluteTime = 0

	var removeUserTimer: (any DispatchSourceTimer)?

	/// Stops the removal timer. The client calls it when it drops the store;
	/// a `deinit` cannot, because the timer is main-actor state.
	func cancelRemoveUserTimer() {
		removeUserTimer?.cancel()
		removeUserTimer = nil
	}
}
