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

import AppKit
import CocoaExtensions
import os

private let alertSoundsDefaultSoundIndex = 0
private let alertSoundsNoSoundIndex = 2

private let notificationConfigurationLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "NotificationConfiguration"
)

@objc(TVCNotificationConfigurationViewController)
@MainActor
public final class NotificationConfigurationViewController: NSObject {
	/** The list used to be [Any] holding configurations and " " for a
	 separator, and its didSet compared `as NSArray` identity, which bridges a
	 fresh NSArray each time and so was always true. */
	public var notifications: [NotificationConfigurationItem] = [] {
		didSet {
			availableAlertsChanged()
		}
	}

	public var allowsMixedState = false {
		didSet {
			if allowsMixedState != oldValue {
				updateMixedState()
			}
		}
	}

	private weak var attachedView: NSView?
	@IBOutlet private var contentView: NSView!
	@IBOutlet private var alertBounceDockIconButton: NSButton!
	@IBOutlet private var alertBounceDockIconRepeatedlyButton: NSButton!
	@IBOutlet private var alertDisableWhileAwayButton: NSButton!
	@IBOutlet private var alertPushNotificationButton: NSButton!
	@IBOutlet private var alertSpeakEventButton: NSButton!
	@IBOutlet private var alertSoundChoiceButton: NSPopUpButton!
	@IBOutlet private var alertTypeChoiceButton: NSPopUpButton!

	private var activeAlert: (any NotificationConfiguration)?
	private var alertSounds: [Any] = []

	override public init() {
		super.init()
		prepareInitialState()
	}

	public func attachToView(_ view: NSView) {
		if attachedView == nil {
			attachedView = view
		} else {
			assertionFailure("View is already attached to a view")
		}

		view.addSubview(contentView)

		view.addConstraints(
			NSLayoutConstraint.constraints(
				withVisualFormat: "H:|-0-[contentView]-0-|",
				options: .directionLeadingToTrailing,
				metrics: nil,
				views: ["contentView": contentView!]
			)
		)

		view.addConstraints(
			NSLayoutConstraint.constraints(
				withVisualFormat: "V:|-0-[contentView]-0-|",
				options: .directionLeadingToTrailing,
				metrics: nil,
				views: ["contentView": contentView!]
			)
		)
	}

	public func reload() {
		guard let alert = activeAlert else {
			return
		}

		alertSpeakEventButton.state = alert.speakEvent
		alertBounceDockIconButton.state = alert.bounceDockIcon
		alertBounceDockIconRepeatedlyButton.isEnabled = alertBounceDockIconButton.state != .off
		alertBounceDockIconRepeatedlyButton.state = alert.bounceDockIconRepeatedly
		alertDisableWhileAwayButton.state = alert.disabledWhileAway
		alertPushNotificationButton.state = alert.pushNotification

		let alertSound = alert.alertSound

		if alertSound == nil {
			alertSoundChoiceButton.selectItem(at: alertSoundsDefaultSoundIndex)
		} else if alertSound == NotificationAlertSound.noSoundPreferenceValue {
			alertSoundChoiceButton.selectItem(at: alertSoundsNoSoundIndex)
		} else if let soundIndex = alertSounds.firstIndex(where: { ($0 as? String) == alertSound }) {
			alertSoundChoiceButton.selectItem(at: soundIndex)
		} else {
			alertSoundChoiceButton.selectItem(at: alertSoundsNoSoundIndex)
		}
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TVCNotificationConfigurationView", owner: self, topLevelObjects: nil)
		updateAvailableSounds()
	}

	private func updateMixedState() {
		alertSpeakEventButton.allowsMixedState = allowsMixedState
		alertBounceDockIconButton.allowsMixedState = allowsMixedState
		alertBounceDockIconRepeatedlyButton.allowsMixedState = allowsMixedState
		alertDisableWhileAwayButton.allowsMixedState = allowsMixedState
		alertPushNotificationButton.allowsMixedState = allowsMixedState
	}

	private func availableAlertsChanged() {
		if notifications.isEmpty {
			resetControls()
		} else {
			updateAlertSelection()
		}
	}

	private func resetControls() {
		alertTypeChoiceButton.removeAllItems()

		alertSpeakEventButton.state = .off
		alertBounceDockIconButton.state = .off
		alertBounceDockIconRepeatedlyButton.isEnabled = false
		alertBounceDockIconRepeatedlyButton.state = .off
		alertDisableWhileAwayButton.state = .off
		alertPushNotificationButton.state = .off

		alertSoundChoiceButton.removeAllItems()
	}

	private func updateAlertSelection() {
		alertTypeChoiceButton.removeAllItems()

		for (index, alert) in notifications.enumerated() {
			guard let configuration = alert.configuration else {
				alertTypeChoiceButton.menu?.addItem(.separator())
				continue
			}

			let item = NSMenuItem()
			item.tag = index
			item.title = configuration.displayName
			alertTypeChoiceButton.menu?.addItem(item)
		}

		alertTypeChoiceButton.selectItem(at: 0)
		onChangedAlertType(nil)
	}

	@IBAction private func onChangedAlertType(_: Any?) {
		// selectedTag() is -1 when nothing is selected, e.g. after the menu is
		// emptied by resetControls().
		let alertTag = alertTypeChoiceButton.selectedTag()
		guard notifications.indices.contains(alertTag) else {
			notificationConfigurationLogger.debug("No notification is selected; nothing to reload")
			activeAlert = nil
			return
		}
		activeAlert = notifications[alertTag].configuration
		reload()
	}

	@IBAction private func onChangedAlertPushNotification(_: Any?) {
		activeAlert?.pushNotification = alertPushNotificationButton.state
	}

	@IBAction private func onChangedAlertSpoken(_: Any?) {
		activeAlert?.speakEvent = alertSpeakEventButton.state
	}

	@IBAction private func onChangedAlertDisableWhileAway(_: Any?) {
		activeAlert?.disabledWhileAway = alertDisableWhileAwayButton.state
	}

	@IBAction private func onChangedAlertBounceDockIcon(_: Any?) {
		activeAlert?.bounceDockIcon = alertBounceDockIconButton.state
		alertBounceDockIconRepeatedlyButton.isEnabled = alertBounceDockIconButton.state == .on
	}

	@IBAction private func onChangedAlertBounceDockIconRepeatedly(_: Any?) {
		activeAlert?.bounceDockIconRepeatedly = alertBounceDockIconRepeatedlyButton.state
	}

	@IBAction private func onChangedAlertSound(_: Any?) {
		var alertSound = alertSoundChoiceButton.titleOfSelectedItem

		if alertSound == NotificationAlertSound.localizedDefaultTitle {
			alertSound = nil
		} else if alertSound == NotificationAlertSound.localizedNoSoundTitle {
			alertSound = NotificationAlertSound.noSoundPreferenceValue
		}

		if let alertSound {
			SoundPlayer.playAlertSound(alertSound)
		}

		activeAlert?.alertSound = alertSound
	}

	private func updateAvailableSounds() {
		alertSoundChoiceButton.removeAllItems()
		alertSounds = availableSounds()

		for alertSound in alertSounds {
			if let name = alertSound as? String {
				let item = NSMenuItem()
				item.title = name
				alertSoundChoiceButton.menu?.addItem(item)
			} else if let item = alertSound as? NSMenuItem {
				alertSoundChoiceButton.menu?.addItem(item)
			}
		}

		alertSoundChoiceButton.selectItem(at: 0)
	}

	private func availableSounds() -> [Any] {
		var sounds: [Any] = [
			NotificationAlertSound.localizedDefaultTitle,
			NSMenuItem.separator(),
			NotificationAlertSound.localizedNoSoundTitle,
			NSMenuItem.separator(),
		]

		sounds.append(contentsOf: SoundPlayer.uniqueListOfSounds())
		return sounds
	}
}
