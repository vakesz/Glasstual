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

/** What a delivered notification carries back when the person clicks it.

 `UNNotificationContent.userInfo` is a property-list dictionary, so the keys
 below are the only place the strings appear; every producer and reader inside
 the application works with the value. It used to be an untyped dictionary
 passed whole from the protocol layer to the delegate callback, with each
 reader guessing at the keys. */
public nonisolated struct NotificationPayload: Equatable, Sendable { // nonisolated: value
	static let clientIdentifierKey = "clientId"
	static let channelIdentifierKey = "channelId"
	private static let fileTransferIdentifierKey = "fileTransferUniqueIdentifier"
	private static let fileTransferTypeKey = "fileTransferNotificationType"

	public var clientIdentifier: String?
	public var channelIdentifier: String?
	/// The transfer a file-transfer notification is about, and its event.
	public var fileTransferIdentifier: String?
	public var fileTransferEventRawValue: Int = 0

	public init(
		clientIdentifier: String? = nil,
		channelIdentifier: String? = nil,
		fileTransferIdentifier: String? = nil,
		fileTransferEventRawValue: Int = 0
	) {
		self.clientIdentifier = clientIdentifier
		self.channelIdentifier = channelIdentifier
		self.fileTransferIdentifier = fileTransferIdentifier
		self.fileTransferEventRawValue = fileTransferEventRawValue
	}

	/// Reads a payload back out of the dictionary UserNotifications kept.
	public init(userInfo: [AnyHashable: Any]) {
		clientIdentifier = userInfo[Self.clientIdentifierKey] as? String
		channelIdentifier = userInfo[Self.channelIdentifierKey] as? String
		fileTransferIdentifier = userInfo[Self.fileTransferIdentifierKey] as? String
		fileTransferEventRawValue = (userInfo[Self.fileTransferTypeKey] as? NSNumber)?.intValue ?? 0
	}

	/// The property list UserNotifications stores with the request.
	public var userInfo: [String: PropertyListValue] {
		var result: [String: PropertyListValue] = [:]

		result[Self.clientIdentifierKey] = clientIdentifier.map(PropertyListValue.string)
		result[Self.channelIdentifierKey] = channelIdentifier.map(PropertyListValue.string)
		result[Self.fileTransferIdentifierKey] = fileTransferIdentifier.map(PropertyListValue.string)

		if fileTransferIdentifier != nil {
			result[Self.fileTransferTypeKey] = .integer(fileTransferEventRawValue)
		}

		return result
	}

	/// The notification group this payload belongs to: one thread per channel,
	/// or per client for a notification the whole connection raised.
	public var threadIdentifier: String? {
		guard let clientIdentifier else {
			return nil
		}

		guard let channelIdentifier else {
			return clientIdentifier
		}

		return "\(clientIdentifier)-\(channelIdentifier)"
	}
}

private let fileTransferCategoryIdentifier = "TXNotificationCategoryIdentifierFileTransfer"
private let fileTransferAcceptActionIdentifier = "TXNotificationActionIdentifierFileTransferAccept"
private let fileTransferDeclineActionIdentifier = "TXNotificationActionIdentifierFileTransferDecline"
private let privateMessageCategoryIdentifier = "TXNotificationCategoryIdentifierPrivateMessage"
private let privateMessageReplyActionIdentifier = "TXNotificationActionIdentifierPrivateMessageReply"

private nonisolated let notificationControllerLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "NotificationController"
)

@MainActor
public final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
	public var areNotificationsDisabled = false {
		didSet {
			guard oldValue != areNotificationsDisabled else { return }
			SharedApplication.sharedSpeechSynthesizer().setNotificationsMuted(
				areNotificationsDisabled || Preferences.Notifications.soundIsMuted.value
			)
			guard areNotificationsDisabled else { return }
			/* Cancellation is the whole retraction mechanism: a delivery that
			 has not reached the system stops, and one that has takes itself
			 back below. */
			deliveryTasks.values.forEach { $0.cancel() }
			deliveryTasks.removeAll()
			let center = UNUserNotificationCenter.current()
			center.removeAllPendingNotificationRequests()
			center.removeAllDeliveredNotifications()
		}
	}

	private var deliveryTasks: [String: Task<Void, Never>] = [:]

	/// The one permission request of this launch, so that a burst of events
	/// raises one prompt rather than one each.
	private var authorizationRequest: Task<Void, Never>?
	/// The main-window selection notification this controller answers.
	private let notifications = NotificationSubscriptions()

	override public init() {
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
	 each play the same sound. `IRCNotificationPolicy.soundPlayback` is what
	 reads it. */
	private(set) var systemSoundDelivery: NotificationSoundDelivery?

	/** Asks the system what it will do with a notification's sound.

	 Read at launch, again once permission has been answered — in the onboarding
	 flow as well as here — and every time the application comes forward,
	 because the person can switch its sounds off in System Settings while it is
	 running and nothing announces that. */
	public func refreshSoundDelivery() async {
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

	private var categoriesToRegister: Set<UNNotificationCategory> {
		let fileTransferAcceptAction = UNNotificationAction(
			identifier: fileTransferAcceptActionIdentifier,
			title: PromptStrings.Action.accept,
			options: [.foreground]
		)

		/* Refusing from the notification is the other half of the decision the
		 request asks for; without it the only way to say no was to open the
		 transfer list and stop the transfer there. */
		let fileTransferDeclineAction = UNNotificationAction(
			identifier: fileTransferDeclineActionIdentifier,
			title: PromptStrings.Action.decline,
			options: [.destructive]
		)

		let fileTransferCategory = UNNotificationCategory(
			identifier: fileTransferCategoryIdentifier,
			actions: [fileTransferAcceptAction, fileTransferDeclineAction],
			intentIdentifiers: [],
			options: [.customDismissAction]
		)

		let privateMessageReplyAction = UNTextInputNotificationAction(
			identifier: privateMessageReplyActionIdentifier,
			title: NotificationStrings.replyActionTitle,
			options: [],
			textInputButtonTitle: NotificationStrings.replySendButtonTitle,
			textInputPlaceholder: NotificationStrings.replyPlaceholder
		)

		let privateMessageCategory = UNNotificationCategory(
			identifier: privateMessageCategoryIdentifier,
			actions: [privateMessageReplyAction],
			intentIdentifiers: [],
			options: [.customDismissAction]
		)

		return [fileTransferCategory, privateMessageCategory]
	}

	private func registerCategories() {
		UNUserNotificationCenter.current().setNotificationCategories(categoriesToRegister)
	}

	private func mainWindowSelectionChanged(_: Notification) {
		guard let mainWindow = AppController.shared.mainWindow,
		      let client = mainWindow.selectedClient
		else {
			return
		}

		dismissNotifications(for: mainWindow.selectedChannel, on: client)
	}

	/** Posts one notification.

	 Who or what it is about is the title, where it happened the subtitle and
	 the detail the body — the shape Messages and Mail use. Every event takes
	 the same shape: titles used to be a second family of "<Category>: <subject>"
	 strings that said in the title what the subtitle already said.

	 `sound` is the alert the event asks for, or `nil` where the person has
	 muted them: the notification carries it so the system plays it with Do Not
	 Disturb, the alert volume and the notification's own settings applied. */
	public func post(
		title: String,
		subtitle: String?,
		body: String?,
		sound: String?,
		userInfo: NotificationPayload?,
		categoryIdentifier: String?
	) {
		var body = body ?? ""

		if Preferences.Messages.removeAllFormatting.value == false {
			body = (body as NSString).stripIRCEffects
		}

		scheduleNotification(
			title: title,
			subtitle: subtitle,
			message: body,
			sound: sound,
			userInfo: userInfo,
			threadIdentifier: userInfo?.threadIdentifier,
			categoryIdentifier: categoryIdentifier
		)
	}

	/// The actions the system offers on a delivered notification, by event.
	public static func categoryIdentifier(for event: NotificationEvent) -> String? {
		switch event {
		case .fileTransferReceiveRequested: fileTransferCategoryIdentifier
		case .newPrivateMessage, .privateMessage: privateMessageCategoryIdentifier
		default: nil
		}
	}

	/// The grouping the payload names; kept as a static so callers that hold
	/// two identifiers rather than a payload can ask for it too.
	public static func threadIdentifier(
		forClient clientIdentifier: String?,
		channel channelIdentifier: String?
	) -> String? {
		NotificationPayload(
			clientIdentifier: clientIdentifier,
			channelIdentifier: channelIdentifier
		).threadIdentifier
	}

	public func scheduleNotification(
		title: String,
		message: String,
		for channel: Channel?,
		on client: IRCClient
	) {
		let payload = NotificationPayload(
			clientIdentifier: client.uniqueIdentifier,
			channelIdentifier: channel?.uniqueIdentifier
		)

		scheduleNotification(
			title: title,
			message: message,
			userInfo: payload,
			threadIdentifier: payload.threadIdentifier,
			categoryIdentifier: nil
		)
	}

	private func scheduleNotification(
		title: String,
		subtitle: String? = nil,
		message: String,
		sound: String? = nil,
		userInfo: NotificationPayload?,
		threadIdentifier: String?,
		categoryIdentifier: String?
	) {
		let content = UNMutableNotificationContent()

		content.title = title
		content.body = message

		if let subtitle, subtitle.isEmpty == false {
			content.subtitle = subtitle
		}

		if let sound {
			content.sound = Self.notificationSound(named: sound)
		}

		if let userInfo {
			content.userInfo = userInfo.userInfo.propertyListObject
		}

		if let categoryIdentifier {
			content.categoryIdentifier = categoryIdentifier
		}

		if let threadIdentifier {
			content.threadIdentifier = threadIdentifier
		}

		/* Unique per notification: the system replaces a delivered notification
		 that carries an identifier it has already seen, and two of the same
		 message in the same channel are two notifications. */
		scheduleNotification(content: content, identifier: UUID().uuidString)
	}

	private func scheduleNotification(content: UNNotificationContent, identifier: String) {
		let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

		scheduleNotification(request: request)
	}

	private func scheduleNotification(request: UNNotificationRequest) {
		guard !areNotificationsDisabled else { return }
		let title = request.content.title
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

	// MARK: - Notification Center Delegate

	public func userNotificationCenter(
		_: UNUserNotificationCenter,
		openSettingsFor _: UNNotification?
	) {
		AppController.shared.menuController?.actionCoordinator.showNotificationPreferences(nil)
	}

	public func userNotificationCenter(
		_: UNUserNotificationCenter,
		willPresent _: UNNotification
	) async -> UNNotificationPresentationOptions {
		Self.presentationOptions(notificationsAreDisabled: areNotificationsDisabled)
	}

	/** How a notification that arrives while Glasstual is frontmost is shown.

	 `.sound` is part of the answer: without it the system shows the banner and
	 drops the sound the notification carries, which is every sound for an event
	 raised while the application is in front. */
	static func presentationOptions(notificationsAreDisabled: Bool) -> UNNotificationPresentationOptions {
		notificationsAreDisabled ? [] : [.list, .banner, .sound]
	}

	public func userNotificationCenter(
		_: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse
	) async {
		notificationResponseReceived(
			actionIdentifier: response.actionIdentifier,
			payload: NotificationPayload(userInfo: response.notification.request.content.userInfo),
			replyMessage: (response as? UNTextInputNotificationResponse)?.userText
		)
	}

	public func dismissNotifications(for channel: Channel?, on client: IRCClient) {
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

	public nonisolated static func isNotification( // nonisolated: pure
		userInfo: [AnyHashable: Any],
		inScopeOfClientIdentifier clientIdentifier: String,
		channelIdentifier: String?
	) -> Bool {
		let payload = NotificationPayload(userInfo: userInfo)

		/* Equality of nil is valid so both channel IDs can be absent. */
		return clientIdentifier == payload.clientIdentifier && channelIdentifier == payload.channelIdentifier
	}

	// MARK: - Notification Callback

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

		/* A reply is answered where it was typed. Raising the main window over
		 it is the one thing the person did not ask for. */
		if actionIdentifier != privateMessageReplyActionIdentifier {
			NSApp.activate()
			AppController.shared.mainWindow.makeKeyAndOrderFront(nil)
		}

		guard let clientId = payload.clientIdentifier, let world = AppController.shared.world else {
			return
		}

		guard let channelId = payload.channelIdentifier else {
			if let client = world.findClient(withId: clientId) {
				AppController.shared.mainWindow.select(client)
			}

			return
		}

		guard let channel = world.findChannel(withId: channelId, onClientWithId: clientId) else {
			return
		}

		let treeItem: TreeItem = channel
		AppController.shared.mainWindow.select(treeItem)

		guard let replyMessage, replyMessage.isEmpty == false else {
			return
		}

		channel.associatedClient?.inputText(replyMessage, destination: treeItem)
	}

	private func fileTransferResponseReceived(
		actionIdentifier: String,
		identifier: String,
		payload: NotificationPayload
	) {
		let center = SharedApplication.sharedFileTransferCenter()
		let clientIdentifier = payload.clientIdentifier

		if actionIdentifier == fileTransferDeclineActionIdentifier {
			center.declineNotification(for: identifier, clientIdentifier: clientIdentifier)
			return
		}

		guard actionIdentifier == UNNotificationDefaultActionIdentifier
			|| actionIdentifier == fileTransferAcceptActionIdentifier
		else {
			return
		}

		let accept = actionIdentifier == fileTransferAcceptActionIdentifier
			&& payload.fileTransferEventRawValue == Int(NotificationEvent.fileTransferReceiveRequested.rawValue)
		/* The transfer may have been cleared before the click arrived. The
		 click still asked for the transfer list, so it is still shown. */
		_ = center.respondToNotification(for: identifier, clientIdentifier: clientIdentifier, accept: accept)
		NSApp.activate()
		center.present()
	}

	// MARK: - Preferences

	public func sound(forEvent event: NotificationEvent, in channel: Channel?) -> String? {
		if let channel, let channelValue = channel.config.sound(forEvent: event) {
			return channelValue
		}

		return Preferences.Notifications.sound(event).storedValue
	}

	public func speakEvent(_ event: NotificationEvent, in channel: Channel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.speakEvent($1) },
			globalValue: { Preferences.Notifications.flag($0, .speak).value }
		)
	}

	public func notificationEnabled(forEvent event: NotificationEvent, in channel: Channel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.notificationEnabled(forEvent: $1) },
			globalValue: { Preferences.Notifications.flag($0, .enabled).value }
		)
	}

	public func disabledWhileAway(forEvent event: NotificationEvent, in channel: Channel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.disabledWhileAway(forEvent: $1) },
			globalValue: { Preferences.Notifications.flag($0, .disabledWhileAway).value }
		)
	}

	public func bounceDockIcon(forEvent event: NotificationEvent, in channel: Channel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.bounceDockIcon(forEvent: $1) },
			globalValue: { Preferences.Notifications.flag($0, .bounceDockIcon).value }
		)
	}

	public func bounceDockIconRepeatedly(forEvent event: NotificationEvent, in channel: Channel?) -> Bool {
		resolve(
			event,
			in: channel,
			channelValue: { $0.bounceDockIconRepeatedly(forEvent: $1) },
			globalValue: { Preferences.Notifications.flag($0, .bounceDockIconRepeatedly).value }
		)
	}

	/// A channel's override wins when it has one; `.inherited` means "no
	/// override", so the application-wide preference answers. Five settings
	/// shared this shape as five byte-identical bodies.
	private func resolve(
		_ event: NotificationEvent,
		in channel: Channel?,
		channelValue: (ChannelConfig, NotificationEvent) -> ChannelEventOverride,
		globalValue: (NotificationEvent) -> Bool
	) -> Bool {
		if let channel {
			switch channelValue(channel.config, event) {
			case .on: return true
			case .off: return false
			case .inherited: break
			}
		}

		return globalValue(event)
	}
}
