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
	private var observerTokens: [(NotificationCenter, NSObjectProtocol)] = []

	func observe(
		_ name: Notification.Name,
		object: AnyObject? = nil,
		center: NotificationCenter = .default,
		using handler: @escaping @MainActor (Notification) -> Void
	) {
		/* Delivered on a later main-queue turn: a handler that ran inside the post
		 that triggered it (a UserDefaults write, for example) would re-enter the
		 poster, and posts can come from any thread. */
		center.publisher(for: name, object: object)
			.receive(on: DispatchQueue.main)
			.sink { notification in
				handler(notification)
			}
			.store(in: &cancellables)
	}

	/// Runs `handler` inline on the posting thread, before the post returns.
	///
	/// Only for notifications that are synchronous contracts and are posted on the
	/// main thread — NSWorkspace's sleep and power-off notifications — where the
	/// system expects the work to be finished by the time the post returns.
	func observeSynchronously(
		_ name: Notification.Name,
		center: NotificationCenter = .default,
		using handler: @escaping @MainActor () -> Void
	) {
		let token = center.addObserver(forName: name, object: nil, queue: nil) { _ in
			/* ISOLATION-EXCEPTION: the whole point of this overload is to run inline on
			 the posting thread, which for these notifications is the main thread. */
			MainActor.assumeIsolated {
				handler()
			}
		}

		observerTokens.append((center, token))
	}

	func cancelAll() {
		cancellables.forEach { $0.cancel() }
		cancellables.removeAll()

		for (center, token) in observerTokens {
			center.removeObserver(token)
		}

		observerTokens.removeAll()
	}
}
