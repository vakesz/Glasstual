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

 A `User` is a value, so a copy taken to be edited would copy this too. The
 client keeps one store per `User.ID` and hands it out by identity, which is
 what makes the removal timer and the away-message clock survive an edit, and
 keeps a throwaway copy from retiring the live person's timer. */
@MainActor
final class UserPersistentStore {
	/// The channels the person is in. The member itself lives in each channel's
	/// member list; this records only where to look.
	var relatedChannels: Set<Channel> = []

	var presentAwayMessageFor301LastEvent: CFAbsoluteTime = 0

	/// Retires the person once they have been in no channel for long enough.
	var removeUserTask: Task<Void, Never>?

	/// Stops the removal timer. The client calls it when it drops the store;
	/// a `deinit` cannot, because the task is main-actor state.
	func cancelRemoveUserTimer() {
		removeUserTask?.cancel()
		removeUserTask = nil
	}
}
