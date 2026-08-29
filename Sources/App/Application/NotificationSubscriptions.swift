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

/// How many values a `bufferedValues` sequence holds while its consumer is
/// between turns. Generous: the sequences below carry notifications and
/// key-value changes, never a stream.
private let observationBufferSize = 64

extension Publisher where Failure == Never {
	/// The publisher's values as an async sequence that survives a burst.
	///
	/// `AsyncPublisher` asks upstream for one value at a time, and neither
	/// `NotificationCenter.Publisher` nor a key-value observing publisher keeps
	/// what it cannot deliver: everything posted between one `next()` and the
	/// request that follows it is dropped on the floor. Five notifications
	/// posted in one main-actor turn arrive as one. Buffering keeps the upstream
	/// demand standing, so the burst arrives whole and in order — which is what
	/// `sink`, with its unlimited demand, used to give.
	var bufferedValues: AsyncPublisher<Publishers.Buffer<Self>> {
		buffer(size: observationBufferSize, prefetch: .keepFull, whenFull: .dropOldest).values
	}
}

/// Owns notification subscriptions for one lifecycle-bound object.
///
/// Notifications are delivered on the main actor because every current
/// consumer coordinates application or AppKit state. Dropping or explicitly
/// cancelling the bag releases every subscription without selector-based
/// observer bookkeeping.
@MainActor
final class NotificationSubscriptions {
	private var tasks: [Task<Void, Never>] = []
	private var observerTokens: [(NotificationCenter, NotificationCenter.ObservationToken)] = []

	func observe(
		_ name: Notification.Name,
		object: AnyObject? = nil,
		center: NotificationCenter = .default,
		using handler: @escaping @MainActor (Notification) -> Void
	) {
		/* Delivered on a later main-actor turn: a handler that ran inside the post
		 that triggered it (a UserDefaults write, for example) would re-enter the
		 poster, and posts can come from any thread. Awaiting the publisher's
		 values inside a main-actor task is what gives the handler isolation the
		 compiler checks; a `sink` closure is nonisolated and cannot. */
		let task = Task { @MainActor in
			for await notification in center.publisher(for: name, object: object).bufferedValues {
				handler(notification)
			}
		}

		tasks.append(task)
	}

	/// Runs `handler` inline on the main actor, before the post returns.
	///
	/// Only for notifications that are synchronous contracts — NSWorkspace's
	/// sleep and power-off notifications — where the system expects the work to
	/// be finished by the time the post returns. `NotificationCenter.Message`
	/// delivery is what carries the isolation here: Foundation calls a
	/// `MainActorMessage` observer on the main actor and traps if the post came
	/// from anywhere else, so nothing has to be assumed about the poster.
	func observeSynchronously<Message: NotificationCenter.MainActorMessage>(
		_ messageType: Message.Type,
		center: NotificationCenter = .default,
		using handler: @escaping @MainActor () -> Void
	) where Message.Subject: AnyObject {
		let token = center.addObserver(for: messageType) { _ in
			handler()
		}

		observerTokens.append((center, token))
	}

	func cancelAll() {
		tasks.forEach { $0.cancel() }
		tasks.removeAll()

		for (center, token) in observerTokens {
			center.removeObserver(token)
		}

		observerTokens.removeAll()
	}
}
