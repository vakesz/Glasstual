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
import UserNotifications

private let onboardingLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "Onboarding"
)

@objc(TDCOnboardingNotificationsStepViewController)
@MainActor
public final class OnboardingNotificationsStepViewController: OnboardingStepViewController {
	private var highlightCheck: NSButton!
	private var privateMessageCheck: NSButton!
	private var soundsCheck: NSButton!
	private var permissionField: NSTextField!
	private var permissionImageView: NSImageView!

	override public var stepTitle: String {
		LocalizedKey("TDCOnboardingWindow[nt1-tt]")
	}

	override public var stepSubtitle: String {
		LocalizedKey("TDCOnboardingWindow[nt1-st]")
	}

	override public func loadView() {
		let view = makeContentView()
		self.view = view

		let highlightCheck = NSButton(
			checkboxWithTitle: LocalizedKey("TDCOnboardingWindow[nt1-hl]"),
			target: self,
			action: #selector(checkboxChanged(_:))
		)

		let privateMessageCheck = NSButton(
			checkboxWithTitle: LocalizedKey("TDCOnboardingWindow[nt1-pm]"),
			target: self,
			action: #selector(checkboxChanged(_:))
		)

		let soundsCheck = NSButton(
			checkboxWithTitle: LocalizedKey("TDCOnboardingWindow[nt1-sn]"),
			target: self,
			action: #selector(checkboxChanged(_:))
		)

		let checkStack = NSStackView(views: [highlightCheck, privateMessageCheck, soundsCheck])
		checkStack.orientation = .vertical
		checkStack.alignment = .leading
		checkStack.spacing = 10
		checkStack.translatesAutoresizingMaskIntoConstraints = false

		let permissionImageView = NSImageView()
		permissionImageView.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: nil)
		permissionImageView.contentTintColor = .secondaryLabelColor
		permissionImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
		permissionImageView.translatesAutoresizingMaskIntoConstraints = false

		let permissionField = NSTextField(wrappingLabelWithString: LocalizedKey("TDCOnboardingWindow[nt1-pr]"))
		permissionField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		permissionField.textColor = .secondaryLabelColor
		permissionField.translatesAutoresizingMaskIntoConstraints = false

		view.addSubview(checkStack)
		view.addSubview(permissionImageView)
		view.addSubview(permissionField)

		let form = NSLayoutGuide()
		view.addLayoutGuide(form)

		NSLayoutConstraint.activate([
			form.widthAnchor.constraint(equalToConstant: 420),
			form.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			form.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),

			checkStack.topAnchor.constraint(equalTo: form.topAnchor),
			checkStack.leadingAnchor.constraint(equalTo: form.leadingAnchor),
			checkStack.trailingAnchor.constraint(lessThanOrEqualTo: form.trailingAnchor),

			permissionImageView.topAnchor.constraint(equalTo: checkStack.bottomAnchor, constant: 32),
			permissionImageView.leadingAnchor.constraint(equalTo: form.leadingAnchor),
			permissionImageView.widthAnchor.constraint(equalToConstant: 28),

			permissionField.leadingAnchor.constraint(equalTo: permissionImageView.trailingAnchor, constant: 10),
			permissionField.trailingAnchor.constraint(equalTo: form.trailingAnchor),
			permissionField.topAnchor.constraint(equalTo: permissionImageView.topAnchor),
		])

		self.highlightCheck = highlightCheck
		self.privateMessageCheck = privateMessageCheck
		self.soundsCheck = soundsCheck
		self.permissionField = permissionField
		self.permissionImageView = permissionImageView
	}

	override public func stepWillAppear() {
		highlightCheck.state = settings.notifyOnHighlight ? .on : .off
		privateMessageCheck.state = settings.notifyOnPrivateMessage ? .on : .off
		soundsCheck.state = settings.playSounds ? .on : .off

		refreshPermissionStatus()
	}

	/** When macOS has already decided, say so instead of promising a prompt. */
	private func refreshPermissionStatus() {
		UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
			let message: String = switch settings.authorizationStatus {
			case .authorized, .provisional:
				LocalizedKey("TDCOnboardingWindow[nt1-pd]")
			case .denied:
				LocalizedKey("TDCOnboardingWindow[nt1-pn]")
			default:
				LocalizedKey("TDCOnboardingWindow[nt1-pr]")
			}

			DispatchQueue.main.async {
				self?.permissionField.stringValue = message
			}
		}
	}

	@objc private func checkboxChanged(_: NSButton) {
		settings.notifyOnHighlight = highlightCheck.state == .on
		settings.notifyOnPrivateMessage = privateMessageCheck.state == .on
		settings.playSounds = soundsCheck.state == .on
	}

	@objc(commitWithError:)
	override public func commit(errorDescription _: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
		checkboxChanged(highlightCheck)

		/* The system prompt appears once; later calls return the stored answer. */
		UNUserNotificationCenter.current().requestAuthorization(
			options: [.alert, .providesAppNotificationSettings]
		) { _, error in
			if let error {
				onboardingLogger.error(
					"Notifications failed to authorize: \(error.localizedDescription, privacy: .public)"
				)
			}
		}

		return true
	}
}
