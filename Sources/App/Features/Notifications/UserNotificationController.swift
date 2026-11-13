// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import os
import UserNotifications

nonisolated let userNotificationControllerLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "UserNotificationController"
)

/** Posts notifications, and answers what the person does with them.

 What is worth a notification is the connection's decision, taken down in
 `Chat/Notifications` (`UserNotificationPolicy`); this owns the delivery: the
 permission prompt, the categories, the burst coalescing and taking a
 notification back when the person mutes them. */
@MainActor
final class UserNotificationController: NSObject, UserNotificationPresenting {
	var areNotificationsDisabled = false {
		didSet {
			guard oldValue != areNotificationsDisabled, areNotificationsDisabled else { return }

			/* Cancellation is the whole retraction mechanism: a delivery that
			 has not reached the system stops, and one that has takes itself
			 back below. */
			deliveries.cancelAll()
			lastAlerts.removeAll()

			let center = UNUserNotificationCenter.current()
			center.removeAllPendingNotificationRequests()
			center.removeAllDeliveredNotifications()
		}
	}

	private var deliveries = UserNotificationDeliveries()

	/** When each conversation last alerted.

	 A busy one-to-one conversation or a channel full of mentions used to raise
	 one banner and one sound per line. The first notification in a thread alerts; every later one
	 stays quiet until `burstWindow` has passed. The quiet ones are still
	 posted, so nothing is lost from Notification Center. */
	private var lastAlerts: [String: ContinuousClock.Instant] = [:]
	private let burstWindow = Duration.seconds(5)

	/// The one permission request of this launch, so that a burst of events
	/// raises one prompt rather than one each.
	private var authorizationRequest: Task<Void, Never>?
	/// When the system last said notifications may be shown. Only that answer
	/// is kept, and only briefly: a denial is always asked again, so allowing
	/// notifications in System Settings takes effect on the next one, and the
	/// system drops anything posted in the seconds after a revocation.
	private var authorizationConfirmedAt: ContinuousClock.Instant?
	private static let authorizationConfirmationLifetime = Duration.seconds(30)
	/// The main-window selection notification this controller answers.
	private let notifications = NotificationSubscriptions()

	override init() {
		super.init()

		prepareInitialState()
	}

	isolated deinit {
		notifications.cancelAll()
		deliveries.cancelAll()
	}

	private func prepareInitialState() {
		UNUserNotificationCenter.current().delegate = self

		notifications.observe(MainWindowSelectionChanged.self) { [weak self] _ in
			self?.mainWindowSelectionChanged()
		}

		registerCategories()
	}

	/** Asks for permission once, the first time there is something to show.

	 Asking at launch puts a permission prompt in front of a person who has not
	 yet done anything that would raise a notification, which is the one moment
	 they have no reason to say yes. The onboarding window explains the
	 permission before asking for it; every other launch asks here, when an
	 event has actually arrived. A refusal is remembered by the system, so this
	 does not ask again. */
	private func requestAuthorizationIfNeeded() async {
		if authorizationRequest == nil {
			authorizationRequest = Task {
				guard await UNUserNotificationCenter.current()
					.notificationSettings().authorizationStatus == .notDetermined
				else {
					return
				}

				do {
					let granted = try await UNUserNotificationCenter.current().requestAuthorization(
						options: [.alert, .sound, .providesAppNotificationSettings]
					)

					userNotificationControllerLogger.info("Notification permission: \(granted, privacy: .public)")
				} catch {
					userNotificationControllerLogger.error(
						"Notifications failed to authorize: \(error.localizedDescription, privacy: .public)"
					)
				}
			}
		}

		await authorizationRequest?.value
	}

	private func registerCategories() {
		UNUserNotificationCenter.current().setNotificationCategories(
			Set(UserNotificationCategory.allCases.map(\.userNotificationCategory))
		)
	}

	private func mainWindowSelectionChanged() {
		guard let mainWindow = AppServices.delegate.mainWindow,
		      let session = mainWindow.selectedSession
		else {
			return
		}

		dismissNotifications(for: mainWindow.selectedConversation, on: session)
	}

	/** Whether a notification in `thread` may alert now, as the first of a
	 burst. Asking claims the alert, so it is asked once per notification.

	 A notification with no thread has nothing to be part of a burst with, so it
	 always alerts. */
	func claimsAlert(inThread thread: String?) -> Bool {
		guard let thread else { return true }

		let now = ContinuousClock.now

		if let last = lastAlerts[thread], now < last + burstWindow {
			return false
		}

		/* Threads whose window has closed no longer decide anything. Dropping
		 them here keeps the table as small as the number of threads alerting
		 now. */
		lastAlerts = lastAlerts.filter { now < $0.value + burstWindow }
		lastAlerts[thread] = now

		return true
	}

	/** Posts one notification.

	 The sound is the system's default alert, carried by the notification so
	 that Do Not Disturb, the alert volume and the notification's own settings
	 apply to it. */
	func post(_ notification: PendingUserNotification) {
		let content = UNMutableNotificationContent()
		content.title = notification.title
		// A notification is plain text whatever the transcript shows.
		content.body = ((notification.body ?? "") as NSString).stripIRCEffects
		content.categoryIdentifier = UserNotificationCategory(event: notification.event).rawValue
		/* A notification behind the first of a burst is added to Notification
		 Center without a banner or a sound, the way Messages adds the rest of a
		 conversation. */
		content.interruptionLevel = notification.alerts ? .active : .passive

		if let subtitle = notification.subtitle, subtitle.isEmpty == false {
			content.subtitle = subtitle
		}

		if notification.playsSound {
			content.sound = .default
		}

		content.userInfo = notification.payload.userInfo.propertyListObject

		if let threadIdentifier = notification.payload.threadIdentifier {
			content.threadIdentifier = threadIdentifier
		}

		schedule(content)
	}

	func announce(_ message: String) {
		guard SettingsStores.live[SettingsKeys.Notifications.announceToVoiceOver],
		      NSWorkspace.shared.isVoiceOverEnabled
		else { return }

		NSAccessibility.post(
			element: NSApp as Any,
			notification: .announcementRequested,
			userInfo: VoiceOverAnnouncement.userInfo(for: message)
		)
	}

	func requestUserAttention() {
		NSApp.requestUserAttention(.informationalRequest)
	}

	func playAlertSound(named name: String) {
		SoundPlayer.playAlertSound(name)
	}

	private func isDeliveryAuthorized() async -> Bool {
		let now = ContinuousClock.now
		if let confirmed = authorizationConfirmedAt, now - confirmed < Self.authorizationConfirmationLifetime {
			return true
		}
		let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
		guard status != .denied else {
			authorizationConfirmedAt = nil
			return false
		}
		authorizationConfirmedAt = ContinuousClock.now
		return true
	}

	private func schedule(_ content: UNNotificationContent) {
		guard !areNotificationsDisabled else { return }

		/* Unique per notification: the system replaces a delivered notification
		 that carries an identifier it has already seen, and two of the same
		 message in the same conversation are two notifications. */
		let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
		let title = content.title

		let task = Task { [weak self] in
			defer { self?.deliveries.complete(request.identifier) }
			await self?.requestAuthorizationIfNeeded()
			guard !Task.isCancelled, await self?.isDeliveryAuthorized() ?? true else { return }
			do {
				let center = UNUserNotificationCenter.current()
				try await center.add(request)
				/* Muting cancelled this while the request was already with the
				 system, so it has to be taken back rather than left showing. */
				if Task.isCancelled {
					center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
					center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
				}
			} catch {
				userNotificationControllerLogger.error(
					"Failed to post notification '\(title, privacy: .private)': \(error.localizedDescription, privacy: .public)"
				)
			}
		}
		deliveries.insert(task, identifier: request.identifier, payload: UserNotificationPayload(userInfo: content.userInfo))
	}

	func dismissNotifications(for conversation: Conversation?, on session: ServerSession) {
		let sessionId = session.uniqueIdentifier
		let conversationId = conversation?.uniqueIdentifier
		deliveries.cancel(for: sessionId, conversationIdentifier: conversationId)

		Task {
			let center = UNUserNotificationCenter.current()
			let requests = await center.pendingNotificationRequests()
			let pendingIdentifiers = requests.compactMap { request -> String? in
				Self.isNotification(
					userInfo: request.content.userInfo,
					inScopeOfSessionIdentifier: sessionId,
					conversationIdentifier: conversationId
				) ? request.identifier : nil
			}

			if pendingIdentifiers.isEmpty == false {
				center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)

				userNotificationControllerLogger.debug(
					"Dismissed \(pendingIdentifiers.count, privacy: .public) pending notifications"
				)
			}

			let notifications = await center.deliveredNotifications()
			let deliveredIdentifiers = notifications.compactMap { notification -> String? in
				Self.isNotification(
					userInfo: notification.request.content.userInfo,
					inScopeOfSessionIdentifier: sessionId,
					conversationIdentifier: conversationId
				) ? notification.request.identifier : nil
			}

			if deliveredIdentifiers.isEmpty == false {
				center.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)

				userNotificationControllerLogger.debug(
					"Dismissed \(deliveredIdentifiers.count, privacy: .public) delivered notifications"
				)
			}
		}
	}

	nonisolated static func isNotification( // nonisolated: pure
		userInfo: [AnyHashable: Any],
		inScopeOfSessionIdentifier sessionIdentifier: String,
		conversationIdentifier: String?
	) -> Bool {
		/* Equality of nil is valid so both conversation IDs can be absent. */
		UserNotificationPayload(userInfo: userInfo)
			.isInScope(of: sessionIdentifier, conversationIdentifier: conversationIdentifier)
	}
}
