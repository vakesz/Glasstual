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

@MainActor
public final class OnboardingNetworkStepViewController: OnboardingStepViewController,
	NetworkPickerViewControllerDelegate
{
	private var picker: NetworkPickerViewController!
	private var connectCheck: NSButton!
	private var channelsLabel: NSTextField!
	private var channelStack: NSStackView!
	private var channelsPlaceholder: NSTextField!

	override public var stepTitle: String {
		OnboardingStrings.FirstNetwork.title
	}

	override public var stepSubtitle: String {
		OnboardingStrings.FirstNetwork.subtitle
	}

	override public var preferredFirstResponder: NSView? {
		nil
	}

	override public func loadView() {
		let view = makeContentView()
		self.view = view

		let picker = NetworkPickerViewController()
		picker.delegate = self
		addChild(picker)

		let pickerView = picker.view

		let connectCheck = NSButton(
			checkboxWithTitle: OnboardingStrings.FirstNetwork.connectWhenFinished,
			target: self,
			action: #selector(connectCheckChanged(_:))
		)
		connectCheck.translatesAutoresizingMaskIntoConstraints = false

		let channelsLabel = NSTextField(labelWithString: OnboardingStrings.FirstNetwork.suggestedChannelsLabel)
		channelsLabel.translatesAutoresizingMaskIntoConstraints = false

		let channelStack = NSStackView()
		channelStack.orientation = .horizontal
		channelStack.spacing = 12
		channelStack.translatesAutoresizingMaskIntoConstraints = false

		let channelsPlaceholder = NSTextField(
			labelWithString: OnboardingStrings.FirstNetwork.suggestedChannelsPlaceholder
		)
		channelsPlaceholder.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		channelsPlaceholder.textColor = .secondaryLabelColor
		channelsPlaceholder.translatesAutoresizingMaskIntoConstraints = false

		view.addSubview(pickerView)
		view.addSubview(connectCheck)
		view.addSubview(channelsLabel)
		view.addSubview(channelStack)
		view.addSubview(channelsPlaceholder)

		NSLayoutConstraint.activate([
			pickerView.topAnchor.constraint(equalTo: view.topAnchor),
			pickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			pickerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

			channelsLabel.topAnchor.constraint(equalTo: pickerView.bottomAnchor, constant: 14),
			channelsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			channelStack.leadingAnchor.constraint(equalTo: channelsLabel.trailingAnchor, constant: 8),
			channelStack.centerYAnchor.constraint(equalTo: channelsLabel.centerYAnchor),
			channelStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
			channelsPlaceholder.leadingAnchor.constraint(equalTo: channelsLabel.trailingAnchor, constant: 8),
			channelsPlaceholder.centerYAnchor.constraint(equalTo: channelsLabel.centerYAnchor),

			connectCheck.topAnchor.constraint(equalTo: channelsLabel.bottomAnchor, constant: 10),
			connectCheck.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			connectCheck.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])

		self.picker = picker
		self.connectCheck = connectCheck
		self.channelsLabel = channelsLabel
		self.channelStack = channelStack
		self.channelsPlaceholder = channelsPlaceholder

		rebuildChannelList()
	}

	override public func stepWillAppear() {
		picker.defaultNickname = settings.nickname
		connectCheck.state = settings.connectWhenFinished ? .on : .off
	}

	@objc private func connectCheckChanged(_ sender: NSButton) {
		settings.connectWhenFinished = sender.state == .on
	}

	// MARK: - Channels

	private func rebuildChannelList() {
		for view in channelStack.arrangedSubviews {
			channelStack.removeArrangedSubview(view)
			view.removeFromSuperview()
		}

		let channels = picker.suggestedChannels

		for channel in channels {
			let check = NSButton(
				checkboxWithTitle: channel,
				target: self,
				action: #selector(channelCheckChanged(_:))
			)
			check.state = .on
			channelStack.addArrangedSubview(check)
		}

		channelsPlaceholder.isHidden = channels.count > 0
		channelCheckChanged(nil)
	}

	@objc private func channelCheckChanged(_: Any?) {
		var channels: [String] = []

		for case let check as NSButton in channelStack.arrangedSubviews where check.state == .on {
			channels.append(check.title)
		}

		settings.channelsToJoin = channels
	}

	// MARK: - Picker Delegate

	public func networkPickerSelectionDidChange(_: NetworkPickerViewController) {
		rebuildChannelList()
	}

	public func networkPickerDidConfirmSelection(_: NetworkPickerViewController) {
		/* Double-clicking a network behaves like pressing the default button. */
		view.window?.defaultButtonCell?.performClick(nil)
	}

	// MARK: - Commit

	override public func commit() throws {
		if picker.hasSelection == false {
			/* Nothing picked means no network; the flow still finishes. */
			settings.clientConfig = nil
			settings.channelsToJoin = []
			return
		}

		try picker.validate()

		settings.clientConfig = picker.clientConfig()
		channelCheckChanged(nil)
	}
}
