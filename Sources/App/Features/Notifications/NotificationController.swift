// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import os
import UserNotifications

nonisolated let notificationControllerLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "NotificationController"
)

/** Posts notifications, and answers what the person does with them.

 What is worth a notification is the connection's decision (`NotificationPolicy`);
 this owns the delivery: the permission prompt, the categories, the burst
 coalescing and taking a notification back when the person mutes them. */
@MainActor
final class NotificationController: NSObject, ClientNotificationPresenting {
	var areNotificationsDisabled = false {
		didSet {
			guard oldValue != areNotificationsDisabled, areNotificationsDisabled else { return }

			/* Cancellation is the whole retraction mechanism: a delivery that
			 has not reached the system stops, and one that has takes itself
			 back below. */
			deliveryTasks.values.forEach { $0.cancel() }
			deliveryTasks.removeAll()
			lastAlerts.removeAll()

			let center = UNUserNotificationCenter.current()
			center.removeAllPendingNotificationRequests()
			center.removeAllDeliveredNotifications()
		}
	}

	private var deliveryTasks: [String: Task<Void, Never>] = [:]

	/** When each conversation last alerted.

	 A busy query or a channel full of mentions used to raise one banner and one
	 sound per line. The first notification in a thread alerts; every later one
	 stays quiet until `burstWindow` has passed. The quiet ones are still
	 posted, so nothing is lost from Notification Center. */
	private var lastAlerts: [String: ContinuousClock.Instant] = [:]
	private let burstWindow = Duration.seconds(5)

	/// The one permission request of this launch, so that a burst of events
	/// raises one prompt rather than one each.
	private var authorizationRequest: Task<Void, Never>?
	/// The main-window selection notification this controller answers.
	private let notifications = NotificationSubscriptions()

	override init() {
		super.init()

		prepareInitialState()
	}

	isolated deinit {
		notifications.cancelAll()
		deliveryTasks.values.forEach { $0.cancel() }
	}

	private func prepareInitialState() {
		UNUserNotificationCenter.current().delegate = self

		notifications.observe(.mainWindowSelectionChanged) { [weak self] notification in
			self?.mainWindowSelectionChanged(notification)
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

					notificationControllerLogger.info("Notification permission: \(granted, privacy: .public)")
				} catch {
					notificationControllerLogger.error(
						"Notifications failed to authorize: \(error.localizedDescription, privacy: .public)"
					)
				}
			}
		}

		await authorizationRequest?.value
	}

	private func registerCategories() {
		UNUserNotificationCenter.current().setNotificationCategories(
			Set(NotificationCategory.allCases.map(\.notificationCategory))
		)
	}

	private func mainWindowSelectionChanged(_: Notification) {
		guard let mainWindow = AppServices.delegate.mainWindow,
		      let client = mainWindow.selectedClient
		else {
			return
		}

		dismissNotifications(for: mainWindow.selectedChannel, on: client)
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
	func post(_ notification: PendingNotification) {
		let content = UNMutableNotificationContent()
		content.title = notification.title
		// A notification is plain text whatever the transcript shows.
		content.body = ((notification.body ?? "") as NSString).stripIRCEffects
		content.categoryIdentifier = NotificationCategory(event: notification.event).rawValue
		content.interruptionLevel = NotificationPolicy.interruptionLevel(alerts: notification.alerts)

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

	/// Posts the notification `/notifybubble` asks for, in the thread of the
	/// channel it names or of the connection.
	func scheduleNotification(
		title: String,
		message: String,
		for channel: Channel?,
		on client: Client
	) {
		post(PendingNotification(
			event: .addressBookMatch,
			title: title,
			subtitle: nil,
			body: message,
			payload: NotificationPayload(
				clientIdentifier: client.uniqueIdentifier,
				channelIdentifier: channel?.uniqueIdentifier
			),
			playsSound: false
		))
	}

	private func schedule(_ content: UNNotificationContent) {
		guard !areNotificationsDisabled else { return }

		/* Unique per notification: the system replaces a delivered notification
		 that carries an identifier it has already seen, and two of the same
		 message in the same channel are two notifications. */
		let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
		let title = content.title

		deliveryTasks[request.identifier] = Task { [weak self] in
			defer { self?.deliveryTasks[request.identifier] = nil }
			await self?.requestAuthorizationIfNeeded()
			guard !Task.isCancelled else { return }
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
				notificationControllerLogger.error(
					"Failed to post notification '\(title, privacy: .private)': \(error.localizedDescription, privacy: .public)"
				)
			}
		}
	}

	func dismissNotifications(for channel: Channel?, on client: Client) {
		let clientId = client.uniqueIdentifier
		let channelId = channel?.uniqueIdentifier

		Task {
			let center = UNUserNotificationCenter.current()
			let requests = await center.pendingNotificationRequests()
			let pendingIdentifiers = requests.compactMap { request -> String? in
				Self.isNotification(
					userInfo: request.content.userInfo,
					inScopeOfClientIdentifier: clientId,
					channelIdentifier: channelId
				) ? request.identifier : nil
			}

			if pendingIdentifiers.isEmpty == false {
				center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)

				notificationControllerLogger.debug(
					"Dismissed \(pendingIdentifiers.count, privacy: .public) pending notifications"
				)
			}

			let notifications = await center.deliveredNotifications()
			let deliveredIdentifiers = notifications.compactMap { notification -> String? in
				Self.isNotification(
					userInfo: notification.request.content.userInfo,
					inScopeOfClientIdentifier: clientId,
					channelIdentifier: channelId
				) ? notification.request.identifier : nil
			}

			if deliveredIdentifiers.isEmpty == false {
				center.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)

				notificationControllerLogger.debug(
					"Dismissed \(deliveredIdentifiers.count, privacy: .public) delivered notifications"
				)
			}
		}
	}

	nonisolated static func isNotification( // nonisolated: pure
		userInfo: [AnyHashable: Any],
		inScopeOfClientIdentifier clientIdentifier: String,
		channelIdentifier: String?
	) -> Bool {
		let payload = NotificationPayload(userInfo: userInfo)

		/* Equality of nil is valid so both channel IDs can be absent. */
		return clientIdentifier == payload.clientIdentifier && channelIdentifier == payload.channelIdentifier
	}
}

/// What the notification center asks the controller, and what the person does
/// with a delivered notification.
extension NotificationController: UNUserNotificationCenterDelegate {
	func userNotificationCenter(
		_: UNUserNotificationCenter,
		openSettingsFor _: UNNotification?
	) {
		AppServices.delegate.menuController?.showNotificationPreferences(nil)
	}

	func userNotificationCenter(
		_: UNUserNotificationCenter,
		willPresent _: UNNotification
	) async -> UNNotificationPresentationOptions {
		Self.presentationOptions(notificationsAreDisabled: areNotificationsDisabled)
	}

	/** How a notification that arrives while Glasstual is frontmost is shown.

	 `.sound` is part of the answer. Without it the system shows the banner and
	 drops the sound the notification carries, which is every sound for an event
	 raised while the application is in front. */
	static func presentationOptions(notificationsAreDisabled: Bool) -> UNNotificationPresentationOptions {
		notificationsAreDisabled ? [] : [.list, .banner, .sound]
	}

	func userNotificationCenter(
		_: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse
	) async {
		notificationResponseReceived(
			actionIdentifier: response.actionIdentifier,
			payload: NotificationPayload(userInfo: response.notification.request.content.userInfo),
			replyMessage: (response as? UNTextInputNotificationResponse)?.userText
		)
	}

	func notificationResponseReceived(
		actionIdentifier: String,
		payload: NotificationPayload,
		replyMessage: String?
	) {
		if actionIdentifier == UNNotificationDismissActionIdentifier {
			return
		}

		if let identifier = payload.fileTransferIdentifier {
			fileTransferResponseReceived(
				actionIdentifier: actionIdentifier,
				identifier: identifier,
				payload: payload
			)

			return
		}

		guard let world = AppServices.clientDirectory else {
			return
		}

		/* A reply is answered where it was typed. Raising the main window over it,
		 or moving its selection to the query, is what the person did not ask for. */
		if actionIdentifier == NotificationCategory.Action.replyToPrivateMessage.rawValue {
			sendReply(replyMessage, for: payload, in: world)
			return
		}

		NSApp.activate()
		AppServices.delegate.mainWindow.makeKeyAndOrderFront(nil)

		guard let clientId = payload.clientIdentifier else {
			return
		}

		guard let channelId = payload.channelIdentifier else {
			if let client = world.findClient(withId: clientId) {
				AppServices.delegate.mainWindow.select(client)
			}

			return
		}

		guard let channel = world.findChannel(withId: channelId, onClientWithId: clientId) else {
			return
		}

		AppServices.delegate.mainWindow.select(channel)
	}

	private func sendReply(_ replyMessage: String?, for payload: NotificationPayload, in world: ClientDirectory) {
		guard let replyMessage, replyMessage.isEmpty == false else {
			return
		}

		guard let destination = Self.replyDestination(for: payload, in: world),
		      let client = destination.associatedClient
		else {
			notificationControllerLogger.error("Dropped a notification reply whose conversation no longer exists")
			return
		}

		client.inputText(replyMessage, destination: destination)
	}

	/** The conversation a reply typed into a notification goes to.

	 The one the notification came from, when it is still open. A private
	 message closed since the notification arrived opens again under the
	 nickname the notification carries: the reply used to go nowhere, without a
	 word, once the query was gone. `nil` when the connection is gone as well. */
	static func replyDestination(for payload: NotificationPayload, in world: ClientDirectory) -> Channel? {
		guard let clientId = payload.clientIdentifier else {
			return nil
		}

		if let channelId = payload.channelIdentifier,
		   let channel = world.findChannel(withId: channelId, onClientWithId: clientId)
		{
			return channel
		}

		guard let queryName = payload.queryName, let client = world.findClient(withId: clientId) else {
			return nil
		}

		return client.findChannelOrCreate(queryName, isPrivateMessage: true)
	}

	private func fileTransferResponseReceived(
		actionIdentifier: String,
		identifier: String,
		payload: NotificationPayload
	) {
		let center = AppServices.fileTransfers
		let clientIdentifier = payload.clientIdentifier

		if actionIdentifier == NotificationCategory.Action.declineFileTransfer.rawValue {
			center.declineNotification(for: identifier, clientIdentifier: clientIdentifier)
			return
		}

		let accepts = actionIdentifier == NotificationCategory.Action.acceptFileTransfer.rawValue

		guard actionIdentifier == UNNotificationDefaultActionIdentifier || accepts else {
			return
		}

		let accept = accepts
			&& payload.fileTransferEventRawValue == Int(NotificationEvent.fileTransferReceiveRequested.rawValue)
		/* The transfer may have been cleared before the click arrived. The click
		 still asked for the transfer list, so the list still opens. */
		_ = center.respondToNotification(for: identifier, clientIdentifier: clientIdentifier, accept: accept)
		NSApp.activate()
		center.present()
	}
}
