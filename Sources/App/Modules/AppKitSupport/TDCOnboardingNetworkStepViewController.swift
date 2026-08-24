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

@objc(TDCOnboardingNetworkStepViewController)
@MainActor
public final class OnboardingNetworkStepViewController: OnboardingStepViewController,
	TDCNetworkPickerViewControllerDelegate
{
	private var picker: TDCNetworkPickerViewController!
	private var connectCheck: NSButton!
	private var channelsLabel: NSTextField!
	private var channelStack: NSStackView!
	private var channelsPlaceholder: NSTextField!

	override public var stepTitle: String {
		LocalizedKey("TDCOnboardingWindow[nw1-tt]")
	}

	override public var stepSubtitle: String {
		LocalizedKey("TDCOnboardingWindow[nw1-st]")
	}

	override public var preferredFirstResponder: NSView? {
		nil
	}

	override public func loadView() {
		let view = makeContentView()
		self.view = view

		let picker = TDCNetworkPickerViewController()
		picker.delegate = self
		addChild(picker)

		let pickerView = picker.view

		let connectCheck = NSButton(
			checkboxWithTitle: LocalizedKey("TDCOnboardingWindow[nw1-cn]"),
			target: self,
			action: #selector(connectCheckChanged(_:))
		)
		connectCheck.translatesAutoresizingMaskIntoConstraints = false

		let channelsLabel = NSTextField(labelWithString: LocalizedKey("TDCOnboardingWindow[nw1-ch]"))
		channelsLabel.translatesAutoresizingMaskIntoConstraints = false

		let channelStack = NSStackView()
		channelStack.orientation = .horizontal
		channelStack.spacing = 12
		channelStack.translatesAutoresizingMaskIntoConstraints = false

		let channelsPlaceholder = NSTextField(labelWithString: LocalizedKey("TDCOnboardingWindow[nw1-ep]"))
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

		for case let check as NSButton in channelStack.arrangedSubviews {
			if check.state == .on {
				channels.append(check.title)
			}
		}

		settings.channelsToJoin = channels
	}

	// MARK: - Picker Delegate

	public func networkPickerSelectionDidChange(_: TDCNetworkPickerViewController) {
		rebuildChannelList()
	}

	public func networkPickerDidConfirmSelection(_: TDCNetworkPickerViewController) {
		/* Double-clicking a network behaves like pressing the default button. */
		view.window?.defaultButtonCell?.performClick(nil)
	}

	// MARK: - Commit

	@objc(commitWithError:)
	override public func commit(errorDescription: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
		if picker.hasSelection == false {
			/* Nothing picked means no network; the flow still finishes. */
			settings.clientConfig = nil
			settings.channelsToJoin = []
			return true
		}

		var pickerError: NSString?
		if picker.validateWithError(&pickerError) == false {
			if let errorDescription {
				errorDescription.pointee = pickerError ?? LocalizedKey("TDCOnboardingWindow[nw1-er]") as NSString
			}

			return false
		}

		settings.clientConfig = picker.clientConfig()
		channelCheckChanged(nil)

		return true
	}
}
