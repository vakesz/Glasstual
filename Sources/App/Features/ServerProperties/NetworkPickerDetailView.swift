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
import Foundation

@MainActor
final class NetworkPickerDetailView: NSView {
	private let titleField = NSTextField(labelWithString: "")
	private let registrationBadge = NSTextField(
		labelWithString: OnboardingStrings.NetworkPicker.registrationRequired
	)
	private let serverAddressField = NSTextField(string: "")
	private let serverPortField = NSTextField(string: "")
	private let securedCheck = NSButton(
		checkboxWithTitle: OnboardingStrings.NetworkPicker.useTLSCheckbox,
		target: nil,
		action: nil
	)
	private let accountBox = NSBox()
	private let accountNameField = NSTextField(string: "")
	private let accountPasswordField = NSSecureTextField()
	private let saslCheck = NSButton(
		checkboxWithTitle: OnboardingStrings.NetworkPicker.useSASLCheckbox,
		target: nil,
		action: nil
	)
	private let registrationNoteField = NSTextField(wrappingLabelWithString: "")
	private let websiteButton = NSButton(title: "", target: nil, action: nil)

	init(
		fieldDelegate: NSTextFieldDelegate,
		actionTarget: AnyObject,
		fieldChangedAction: Selector,
		openWebsiteAction: Selector
	) {
		super.init(frame: .zero)

		configureControls(
			fieldDelegate: fieldDelegate,
			actionTarget: actionTarget,
			fieldChangedAction: fieldChangedAction,
			openWebsiteAction: openWebsiteAction
		)
		installAccountContents()
		installDetailContents()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	var serverAddress: String {
		serverAddressField.stringValue
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
	}

	var serverPort: UInt16 {
		let port = serverPortField.integerValue

		guard port > 0, port <= Int(UInt16.max) else {
			return 0
		}

		return UInt16(port)
	}

	var prefersSecuredConnection: Bool {
		securedCheck.state == .on
	}

	var accountName: String {
		guard accountBox.isHidden == false else {
			return ""
		}

		return accountNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	var accountPassword: String {
		guard accountBox.isHidden == false else {
			return ""
		}

		return accountPasswordField.stringValue
	}

	var usesSASL: Bool {
		accountBox.isHidden == false && saslCheck.state == .on && accountPassword.isEmpty == false
	}

	func display(network: Network?, customServerSelected: Bool, defaultNickname: String?) {
		if let network {
			display(network: network)
		} else {
			displayCustomServerDefaults()
		}

		accountNameField.stringValue = defaultNickname ?? ""
		accountPasswordField.stringValue = ""
		isHidden = network == nil && customServerSelected == false
		accountBox.isHidden = network?.accountFieldsApply == false
	}

	func displayCustomServer(address: String, port: UInt16, secured: Bool) {
		serverAddressField.stringValue = address

		if port > 0 {
			serverPortField.integerValue = Int(port)
		}

		securedCheck.state = secured ? .on : .off
	}

	func updateDefaultNickname(_ nickname: String?) {
		accountNameField.stringValue = nickname ?? ""
	}

	func ownsAccountNameField(_ object: AnyObject) -> Bool {
		object === accountNameField
	}

	private func configureControls(
		fieldDelegate: NSTextFieldDelegate,
		actionTarget: AnyObject,
		fieldChangedAction: Selector,
		openWebsiteAction: Selector
	) {
		translatesAutoresizingMaskIntoConstraints = false

		titleField.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
		titleField.lineBreakMode = .byTruncatingTail

		registrationBadge.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
		registrationBadge.textColor = .systemOrange
		registrationBadge.wantsLayer = true
		registrationBadge.layer?.cornerRadius = 4
		registrationBadge.layer?.borderWidth = 1
		registrationBadge.layer?.borderColor = NSColor.systemOrange.cgColor
		registrationBadge.alignment = .center
		registrationBadge.isHidden = true

		serverAddressField.placeholderString = OnboardingStrings.NetworkPicker.serverAddressPlaceholder
		serverAddressField.delegate = fieldDelegate

		serverPortField.placeholderString = OnboardingStrings.NetworkPicker.portPlaceholder
		serverPortField.delegate = fieldDelegate
		serverPortField.alignment = .right
		serverPortField.formatter = makePortFormatter()

		securedCheck.target = actionTarget
		securedCheck.action = fieldChangedAction

		accountBox.title = OnboardingStrings.NetworkPicker.accountGroup
		accountBox.titlePosition = .atTop

		accountNameField.delegate = fieldDelegate
		accountPasswordField.delegate = fieldDelegate

		saslCheck.target = actionTarget
		saslCheck.action = fieldChangedAction

		registrationNoteField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		registrationNoteField.textColor = .secondaryLabelColor
		registrationNoteField.isSelectable = true
		registrationNoteField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		websiteButton.target = actionTarget
		websiteButton.action = openWebsiteAction
		websiteButton.isBordered = false
		websiteButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		websiteButton.contentTintColor = .linkColor

		[
			titleField,
			registrationBadge,
			serverAddressField,
			serverPortField,
			securedCheck,
			accountBox,
			accountNameField,
			accountPasswordField,
			saslCheck,
			registrationNoteField,
			websiteButton,
		].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
	}

	private func installAccountContents() {
		guard let accountContent = accountBox.contentView else {
			preconditionFailure("NSBox must provide a content view")
		}

		let accountNameLabel = makeLabel(OnboardingStrings.NetworkPicker.accountNameLabel)
		let passwordLabel = makeLabel(OnboardingStrings.NetworkPicker.passwordLabel)

		accountContent.addSubview(accountNameLabel)
		accountContent.addSubview(accountNameField)
		accountContent.addSubview(passwordLabel)
		accountContent.addSubview(accountPasswordField)
		accountContent.addSubview(saslCheck)
		accountContent.addSubview(registrationNoteField)
		accountContent.addSubview(websiteButton)

		NSLayoutConstraint.activate([
			accountNameLabel.topAnchor.constraint(equalTo: accountContent.topAnchor, constant: 8),
			accountNameLabel.leadingAnchor.constraint(equalTo: accountContent.leadingAnchor, constant: 8),
			accountNameLabel.widthAnchor.constraint(equalToConstant: 110),
			accountNameField.leadingAnchor.constraint(equalTo: accountNameLabel.trailingAnchor, constant: 8),
			accountNameField.trailingAnchor.constraint(equalTo: accountContent.trailingAnchor, constant: -8),
			accountNameField.firstBaselineAnchor.constraint(equalTo: accountNameLabel.firstBaselineAnchor),
			passwordLabel.topAnchor.constraint(equalTo: accountNameField.bottomAnchor, constant: 8),
			passwordLabel.trailingAnchor.constraint(equalTo: accountNameLabel.trailingAnchor),
			passwordLabel.widthAnchor.constraint(equalTo: accountNameLabel.widthAnchor),
			accountPasswordField.leadingAnchor.constraint(equalTo: accountNameField.leadingAnchor),
			accountPasswordField.trailingAnchor.constraint(equalTo: accountNameField.trailingAnchor),
			accountPasswordField.firstBaselineAnchor.constraint(equalTo: passwordLabel.firstBaselineAnchor),
			saslCheck.topAnchor.constraint(equalTo: accountPasswordField.bottomAnchor, constant: 8),
			saslCheck.leadingAnchor.constraint(equalTo: accountNameField.leadingAnchor),
			registrationNoteField.topAnchor.constraint(equalTo: saslCheck.bottomAnchor, constant: 6),
			registrationNoteField.leadingAnchor.constraint(equalTo: accountNameField.leadingAnchor),
			registrationNoteField.trailingAnchor.constraint(equalTo: accountNameField.trailingAnchor),
			websiteButton.topAnchor.constraint(equalTo: registrationNoteField.bottomAnchor, constant: 2),
			websiteButton.leadingAnchor.constraint(equalTo: accountNameField.leadingAnchor),
			websiteButton.bottomAnchor.constraint(equalTo: accountContent.bottomAnchor, constant: -6),
		])
	}

	private func installDetailContents() {
		let addressLabel = makeLabel(OnboardingStrings.NetworkPicker.serverAddressLabel)
		let portLabel = makeLabel(OnboardingStrings.NetworkPicker.portLabel)

		addSubview(titleField)
		addSubview(registrationBadge)
		addSubview(addressLabel)
		addSubview(serverAddressField)
		addSubview(portLabel)
		addSubview(serverPortField)
		addSubview(securedCheck)
		addSubview(accountBox)

		NSLayoutConstraint.activate([
			titleField.topAnchor.constraint(equalTo: topAnchor),
			titleField.leadingAnchor.constraint(equalTo: leadingAnchor),
			registrationBadge.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 8),
			registrationBadge.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
			registrationBadge.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
			registrationBadge.widthAnchor
				.constraint(equalToConstant: registrationBadge.intrinsicContentSize.width + 12),
			registrationBadge.heightAnchor
				.constraint(equalToConstant: registrationBadge.intrinsicContentSize.height + 2),
			addressLabel.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 10),
			addressLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
			addressLabel.widthAnchor.constraint(equalToConstant: 122),
			serverAddressField.leadingAnchor.constraint(equalTo: addressLabel.trailingAnchor, constant: 8),
			serverAddressField.firstBaselineAnchor.constraint(equalTo: addressLabel.firstBaselineAnchor),
			portLabel.leadingAnchor.constraint(equalTo: serverAddressField.trailingAnchor, constant: 12),
			portLabel.firstBaselineAnchor.constraint(equalTo: addressLabel.firstBaselineAnchor),
			serverPortField.leadingAnchor.constraint(equalTo: portLabel.trailingAnchor, constant: 8),
			serverPortField.widthAnchor.constraint(equalToConstant: 64),
			serverPortField.trailingAnchor.constraint(equalTo: trailingAnchor),
			serverPortField.firstBaselineAnchor.constraint(equalTo: addressLabel.firstBaselineAnchor),
			securedCheck.topAnchor.constraint(equalTo: serverAddressField.bottomAnchor, constant: 8),
			securedCheck.leadingAnchor.constraint(equalTo: serverAddressField.leadingAnchor),
			accountBox.topAnchor.constraint(equalTo: securedCheck.bottomAnchor, constant: 8),
			accountBox.leadingAnchor.constraint(equalTo: leadingAnchor),
			accountBox.trailingAnchor.constraint(equalTo: trailingAnchor),
			accountBox.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
		])
	}

	private func display(network: Network) {
		titleField.stringValue = network.networkName
		serverAddressField.stringValue = network.serverAddress
		serverPortField.integerValue = Int(network.serverPort)
		securedCheck.state = network.prefersSecuredConnection ? .on : .off
		saslCheck.state = network.saslSupported ? .on : .off
		saslCheck.isEnabled = network.saslSupported
		registrationNoteField.stringValue = network.registrationNote ?? ""
		registrationBadge.isHidden = network.registration != .required

		if let website = network.website, website.isEmpty == false {
			websiteButton.title = website
			websiteButton.isHidden = false
		} else {
			websiteButton.title = ""
			websiteButton.isHidden = true
		}
	}

	private func displayCustomServerDefaults() {
		titleField.stringValue = OnboardingStrings.NetworkPicker.customServerTitle
		serverAddressField.stringValue = ""
		serverPortField.stringValue = OnboardingStrings.NetworkPicker.portPlaceholder
		securedCheck.state = .on
		saslCheck.state = .on
		saslCheck.isEnabled = true
		registrationNoteField.stringValue = ""
		registrationBadge.isHidden = true
		websiteButton.title = ""
		websiteButton.isHidden = true
	}

	private func makeLabel(_ title: String) -> NSTextField {
		let label = NSTextField(labelWithString: title)
		label.alignment = .right
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}

	private func makePortFormatter() -> NumberFormatter {
		let formatter = NumberFormatter()
		formatter.numberStyle = .none
		formatter.minimum = 1
		formatter.maximum = 65535
		formatter.allowsFloats = false
		formatter.usesGroupingSeparator = false
		return formatter
	}
}
