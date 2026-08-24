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

import AppKit
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
	@objc public var notifications: [Any] = [] {
		didSet {
			if (notifications as NSArray) !== (oldValue as NSArray) {
				availableAlertsChanged()
			}
		}
	}

	@objc public var allowsMixedState = false {
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

	private var activeAlert: NotificationConfiguration? {
		didSet {
			if activeAlert !== oldValue {
				stopObservingActiveAlert(oldValue)
				startObservingActiveAlert()
			}
		}
	}

	private var activeAlertPropertyChangedByUser = false
	private var alertSounds: [Any] = []

	override public init() {
		super.init()
		prepareInitialState()
	}

	deinit {
		MainActor.assumeIsolated {
			stopObservingActiveAlert(activeAlert)
		}
	}

	@objc public func attachToView(_ view: NSView) {
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

	@objc public func reload() {
		guard let alert = activeAlert else {
			return
		}

		alertSpeakEventButton.state = NSControl.StateValue(rawValue: Int(alert.speakEvent))
		alertBounceDockIconButton.state = NSControl.StateValue(rawValue: Int(alert.bounceDockIcon))
		alertBounceDockIconRepeatedlyButton.isEnabled = alertBounceDockIconButton.state != .off
		alertBounceDockIconRepeatedlyButton.state = NSControl.StateValue(rawValue: Int(alert.bounceDockIconRepeatedly))
		alertDisableWhileAwayButton.state = NSControl.StateValue(rawValue: Int(alert.disabledWhileAway))
		alertPushNotificationButton.state = NSControl.StateValue(rawValue: Int(alert.pushNotification))

		let alertSound = alert.alertSound

		if alertSound == nil {
			alertSoundChoiceButton.selectItem(at: alertSoundsDefaultSoundIndex)
		} else if alertSound == TLONotificationAlertSound.TXNoAlertSoundPreferenceValue.rawValue {
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
			if let configuration = alert as? NotificationConfiguration {
				let item = NSMenuItem()
				item.tag = index
				item.title = configuration.displayName
				alertTypeChoiceButton.menu?.addItem(item)
			} else {
				alertTypeChoiceButton.menu?.addItem(.separator())
			}
		}

		alertTypeChoiceButton.selectItem(at: 0)
		onChangedAlertType(nil)
	}

	@IBAction private func onChangedAlertType(_: Any?) {
		let alertTag = alertTypeChoiceButton.selectedTag()
		activeAlert = notifications[alertTag] as? NotificationConfiguration
		reload()
	}

	@IBAction private func onChangedAlertPushNotification(_: Any?) {
		activeAlertPropertyChangedByUser = true
		activeAlert?.pushNotification = UInt(alertPushNotificationButton.state.rawValue)
	}

	@IBAction private func onChangedAlertSpoken(_: Any?) {
		activeAlertPropertyChangedByUser = true
		activeAlert?.speakEvent = UInt(alertSpeakEventButton.state.rawValue)
	}

	@IBAction private func onChangedAlertDisableWhileAway(_: Any?) {
		activeAlertPropertyChangedByUser = true
		activeAlert?.disabledWhileAway = UInt(alertDisableWhileAwayButton.state.rawValue)
	}

	@IBAction private func onChangedAlertBounceDockIcon(_: Any?) {
		activeAlertPropertyChangedByUser = true
		activeAlert?.bounceDockIcon = UInt(alertBounceDockIconButton.state.rawValue)
		alertBounceDockIconRepeatedlyButton.isEnabled = alertBounceDockIconButton.state == .on
	}

	@IBAction private func onChangedAlertBounceDockIconRepeatedly(_: Any?) {
		activeAlertPropertyChangedByUser = true
		activeAlert?.bounceDockIconRepeatedly = UInt(alertBounceDockIconRepeatedlyButton.state.rawValue)
	}

	@IBAction private func onChangedAlertSound(_: Any?) {
		activeAlertPropertyChangedByUser = true

		var alertSound = alertSoundChoiceButton.titleOfSelectedItem

		if alertSound == NotificationConfiguration.localizedAlertDefaultSoundTitle() {
			alertSound = nil
		} else if alertSound == NotificationConfiguration.localizedAlertNoSoundTitle() {
			alertSound = TLONotificationAlertSound.TXNoAlertSoundPreferenceValue.rawValue
		}

		if let alertSound {
			SoundPlayer.playAlertSound(alertSound)
		}

		activeAlert?.alertSound = alertSound
	}

	private func startObservingActiveAlert() {
		guard let activeAlert else {
			return
		}

		for keyPath in [
			"alertSound",
			"speakEvent",
			"pushNotification",
			"disabledWhileAway",
			"bounceDockIcon",
			"bounceDockIconRepeatedly",
		] {
			activeAlert.addObserver(self, forKeyPath: keyPath, options: .new, context: nil)
		}
	}

	private func stopObservingActiveAlert(_ alert: NotificationConfiguration?) {
		guard let alert else {
			return
		}

		for keyPath in [
			"alertSound",
			"speakEvent",
			"pushNotification",
			"disabledWhileAway",
			"bounceDockIcon",
			"bounceDockIconRepeatedly",
		] {
			alert.removeObserver(self, forKeyPath: keyPath)
		}
	}

	override public func observeValue(
		forKeyPath keyPath: String?,
		of object: Any?,
		change _: [NSKeyValueChangeKey: Any]?,
		context _: UnsafeMutableRawPointer?
	) {
		if object as AnyObject? === activeAlert {
			if activeAlertPropertyChangedByUser {
				activeAlertPropertyChangedByUser = false
				return
			}

			notificationConfigurationLogger.debug(
				"Reloading user interface because key \(keyPath ?? "nil", privacy: .public) changed remotely"
			)
			reload()
		}
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
			NotificationConfiguration.localizedAlertDefaultSoundTitle(),
			NSMenuItem.separator(),
			NotificationConfiguration.localizedAlertNoSoundTitle(),
			NSMenuItem.separator(),
		]

		sounds.append(contentsOf: SoundPlayer.uniqueListOfSounds())
		return sounds
	}
}
