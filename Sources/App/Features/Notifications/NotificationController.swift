/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import os
import UserNotifications

nonisolated let notificationControllerLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "NotificationController"
)

@MainActor
final class NotificationController: NSObject {
	var areNotificationsDisabled = false {
		didSet {
			guard oldValue != areNotificationsDisabled else { return }
			AppServices.speech.setNotificationsMuted(
				areNotificationsDisabled || Preferences.Notifications.soundIsMuted.value
			)
			guard areNotificationsDisabled else { return }
			/* Cancellation is the whole retraction mechanism: a delivery that
			 has not reached the system stops, and one that has takes itself
			 back below. */
			deliveryTasks.values.forEach { $0.cancel() }
			deliveryTasks.removeAll()
			bursts.reset()
			let center = UNUserNotificationCenter.current()
			center.removeAllPendingNotificationRequests()
			center.removeAllDeliveredNotifications()
		}
	}

	private var deliveryTasks: [String: Task<Void, Never>] = [:]

	/// Which notifications in a burst may alert. See `claimsAlert(inThread:)`.
	private var bursts = NotificationBurstCoalescer()

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

	/** What the system does with the sound a notification carries, or `nil`
	 while the question is still open.

	 A notification is where a sound belongs: the system honours Do Not Disturb,
	 the notification's own settings and the alert volume, none of which an
	 `AudioServicesPlayAlertSound` behind its back does. The application only
	 plays one itself where the notification is delivered but its sound is not.

	 The answer is a question for the system, so it is not here yet when the
	 first events of a launch arrive, and it is not here at all until the person
	 has answered the permission prompt. `nil` says so rather than claiming the
	 system plays nothing, which would have the application and the notification
	 each play the same sound. `NotificationPolicy.soundPlayback` is what
	 reads it. */
	private(set) var systemSoundDelivery: NotificationSoundDelivery?

	/** Asks the system what it will do with a notification's sound.

	 Read at launch, again once permission has been answered — in the onboarding
	 flow as well as here — and every time the application comes forward,
	 because the person can switch its sounds off in System Settings while it is
	 running and nothing announces that. */
	func refreshSoundDelivery() async {
		let settings = await UNUserNotificationCenter.current().notificationSettings()

		systemSoundDelivery = switch settings.authorizationStatus {
		case .authorized, .provisional, .ephemeral:
			settings.soundSetting == .enabled ? .system : .silenced
		case .denied:
			.refused
		// `.notDetermined`, and whatever a later release adds: nobody has said.
		default:
			nil
		}
	}

	private func prepareInitialState() {
		UNUserNotificationCenter.current().delegate = self

		Task { await refreshSoundDelivery() }

		notifications.observe(.mainWindowSelectionChanged) { [weak self] notification in
			self?.mainWindowSelectionChanged(notification)
		}

		// Cheapest moment to notice a change made in System Settings.
		notifications.observe(NSApplication.didBecomeActiveNotification) { [weak self] _ in
			Task { await self?.refreshSoundDelivery() }
		}

		registerCategories()
	}

	/** The sound a notification carries.

	 A name the system cannot resolve falls back to the default notification
	 sound: still the system playing something at the right moment, which is
	 the point, rather than silence or a sound played behind its back. */
	static func notificationSound(named name: String) -> UNNotificationSound? {
		guard name != NotificationAlertSound.noSoundPreferenceValue else { return nil }
		guard name != SoundPlayer.beepSoundName else { return .default }

		return UNNotificationSound(named: UNNotificationSoundName(name))
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

				await refreshSoundDelivery()
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
	 burst. The ones after it in the same burst are posted quietly, and any sound
	 the application would play for them is skipped as well. */
	func claimsAlert(inThread thread: String?) -> Bool {
		bursts.claimsAlert(inThread: thread, at: .now)
	}

	/** Posts one notification.

	 Who or what it is about is the title, where it happened the subtitle and
	 the detail the body, the shape Messages and Mail use. Every event takes the
	 same shape. Titles used to be a second family of "<Category>: <subject>"
	 strings that said in the title what the subtitle already said.

	 `sound` is the alert the event asks for, or `nil` where the person has
	 muted them. The notification carries it so the system plays it with Do Not
	 Disturb, the alert volume and the notification's own settings applied. */
	func post(
		title: String,
		subtitle: String?,
		body: String?,
		sound: String?,
		userInfo: NotificationPayload?,
		category: NotificationCategory,
		interruptionLevel: UNNotificationInterruptionLevel
	) {
		// A notification is plain text whatever the transcript shows.
		let body = ((body ?? "") as NSString).stripIRCEffects

		let content = UNMutableNotificationContent()
		content.title = title
		content.body = body
		content.categoryIdentifier = category.rawValue
		content.interruptionLevel = interruptionLevel

		if let subtitle, subtitle.isEmpty == false {
			content.subtitle = subtitle
		}

		if let sound {
			content.sound = Self.notificationSound(named: sound)
		}

		if let userInfo {
			content.userInfo = userInfo.userInfo.propertyListObject
		}

		if let threadIdentifier = userInfo?.threadIdentifier {
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
		post(
			title: title,
			subtitle: nil,
			body: message,
			sound: nil,
			userInfo: NotificationPayload(
				clientIdentifier: client.uniqueIdentifier,
				channelIdentifier: channel?.uniqueIdentifier
			),
			category: .activity,
			interruptionLevel: .active
		)
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
