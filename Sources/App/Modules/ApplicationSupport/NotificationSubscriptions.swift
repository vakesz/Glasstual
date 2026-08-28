/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Combine
import Foundation

/// Owns notification subscriptions for one lifecycle-bound object.
///
/// Notifications are delivered on the main actor because every current
/// consumer coordinates application or AppKit state. Dropping or explicitly
/// cancelling the bag releases every subscription without selector-based
/// observer bookkeeping.
@MainActor
final class NotificationSubscriptions {
	private var cancellables: Set<AnyCancellable> = []

	func observe(
		_ name: Notification.Name,
		object: AnyObject? = nil,
		center: NotificationCenter = .default,
		using handler: @escaping @MainActor (Notification) -> Void
	) {
		center.publisher(for: name, object: object)
			.sink { notification in
				/* NSWorkspace's sleep and power-off notifications are synchronous
				 contracts — the system expects the work to be finished by the time the
				 notification returns — so deliver directly when already on the main
				 actor rather than always deferring to a later runloop turn. */
				if Thread.isMainThread {
					MainActor.assumeIsolated {
						handler(notification)
					}

					return
				}

				performAsynchronouslyOnMainQueue {
					MainActor.assumeIsolated {
						handler(notification)
					}
				}
			}
			.store(in: &cancellables)
	}

	func cancelAll() {
		cancellables.forEach { $0.cancel() }
		cancellables.removeAll()
	}
}
