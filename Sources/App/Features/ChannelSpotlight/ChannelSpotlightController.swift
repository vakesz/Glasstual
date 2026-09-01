/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Observation
import SwiftUI

/// What `ChannelSpotlightController` reports back.
@MainActor
public protocol ChannelSpotlightControllerDelegate: AnyObject {
	func channelSpotlightController(_ sender: ChannelSpotlightController, selectChannel channel: IRCChannel)
	func channelSpotlightControllerWillClose(_ sender: ChannelSpotlightController)
}

@MainActor
@Observable
final class ChannelSpotlightModel {
	var searchText = "" {
		didSet {
			guard searchText != oldValue else { return }
			refreshDisplayedResults()
		}
	}

	private(set) var allResults: [ChannelSpotlightSearchResult] = []
	private(set) var displayedResults: [ChannelSpotlightSearchResult] = []
	var selectedResultID: ChannelSpotlightSearchResult.ID?

	private var restrictedClientID: String?

	func populate() {
		allResults = AppController.shared.world.clientList.flatMap { client in
			client.channelList.map(ChannelSpotlightSearchResult.init(channel:))
		}
		refreshDisplayedResults()
	}

	func updateClientRestriction() {
		if Preferences.Appearance.channelNavigationIsServerSpecific.value {
			restrictedClientID = AppController.shared.mainWindow.selectedClient?.uniqueIdentifier ?? ""
		} else {
			restrictedClientID = nil
		}
		refreshDisplayedResults()
	}

	func selectRelativeResult(offset: Int) {
		guard displayedResults.isEmpty == false else { return }
		let currentIndex = selectedResultID.flatMap { selectedID in
			displayedResults.firstIndex { $0.id == selectedID }
		} ?? 0
		let nextIndex = (currentIndex + offset + displayedResults.count) % displayedResults.count
		selectedResultID = displayedResults[nextIndex].id
	}

	func result(at index: Int) -> ChannelSpotlightSearchResult? {
		guard displayedResults.indices.contains(index) else { return nil }
		return displayedResults[index]
	}

	var selectedResult: ChannelSpotlightSearchResult? {
		guard let selectedResultID else { return displayedResults.first }
		return displayedResults.first { $0.id == selectedResultID }
	}

	private func refreshDisplayedResults() {
		for result in allResults {
			result.recalculateDistance(with: searchText)
		}

		var admitted: Set<ChannelSpotlightSearchResult.ID> = []
		displayedResults = ChannelSpotlightSearchResults.displayed(
			allResults,
			restrictedToClient: restrictedClientID,
			distance: \.distance,
			clientID: \.clientId
		)
		.filter { admitted.insert($0.id).inserted }

		if let selectedResultID,
		   displayedResults.contains(where: { $0.id == selectedResultID })
		{
			return
		}
		selectedResultID = displayedResults.first?.id
	}
}

@objc(TDCChannelSpotlightController)
@MainActor
public final class ChannelSpotlightController: WindowBase, NSWindowDelegate {
	private static let width = 600.0
	private static let searchHeight = 76.0
	private static let emptyResultHeight = 72.0
	private static let resultHeight = 54.0
	private static let maximumVisibleResults = 6

	private let model = ChannelSpotlightModel()
	private lazy var notifications = NotificationSubscriptions()
	private var keyEventMonitor: Any?

	private var spotlightDelegate: (any ChannelSpotlightControllerDelegate)? {
		delegate as? any ChannelSpotlightControllerDelegate
	}

	override public init() {
		super.init()
		installWindow()
		prepareNotifications()
		model.populate()
		model.updateClientRestriction()
	}

	private func installWindow() {
		let rootView = ChannelSpotlightView(
			model: model,
			select: { [weak self] result in self?.select(result) },
			layoutChanged: { [weak self] in self?.resizeToFitResults() }
		)
		let panel = ChannelSpotlightPanel(
			contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.searchHeight),
			styleMask: [.titled, .closable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		panel.contentViewController = NSHostingController(rootView: rootView)
		panel.delegate = self
		panel.isReleasedWhenClosed = false
		panel.isRestorable = false
		panel.tabbingMode = .disallowed
		panel.preventsApplicationTerminationWhenModal = false
		panel.title = ChannelSpotlightStrings.accessibilityTitle
		window = panel
	}

	private func prepareNotifications() {
		notifications.observe(.ircWorldClientListWasModified) { [weak self] _ in
			self?.reloadResults()
		}
		notifications.observe(Notification.Name("IRCClientChannelListWasModifiedNotification")) { [weak self] _ in
			self?.reloadResults()
		}
		notifications.observe(.mainWindowSelectionChanged) { [weak self] _ in
			self?.model.updateClientRestriction()
			self?.resizeToFitResults()
		}
		notifications.observe(.textualUserDefaultsDidChange) { [weak self] notification in
			guard notification.userInfo?["changedKey"] as? String == "ChannelNavigationIsServerSpecific"
			else { return }
			self?.model.updateClientRestriction()
			self?.resizeToFitResults()
		}
	}

	private func reloadResults() {
		model.populate()
		model.updateClientRestriction()
		resizeToFitResults()
	}

	private func installKeyMonitorIfNeeded() {
		guard keyEventMonitor == nil else { return }
		keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			self?.handleKeyEvent(event) ?? event
		}
	}

	private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
		guard window.isKeyWindow else { return event }

		let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		if modifiers == .command, let number = Int(event.characters ?? ""), (0 ... 9).contains(number) {
			select(model.result(at: number == 0 ? 9 : number - 1))
			return nil
		}

		switch event.keyCode {
		case 36, 76:
			select(model.selectedResult)
			return nil
		case 53:
			if model.searchText.isEmpty {
				close()
			} else {
				model.searchText = ""
				resizeToFitResults()
			}
			return nil
		case 125:
			model.selectRelativeResult(offset: 1)
			return nil
		case 126:
			model.selectRelativeResult(offset: -1)
			return nil
		default:
			return event
		}
	}

	private func select(_ result: ChannelSpotlightSearchResult?) {
		guard let channel = result?.channel else { return }
		spotlightDelegate?.channelSpotlightController(self, selectChannel: channel)
		close()
	}

	private func resizeToFitResults() {
		guard let window else { return }
		let resultAreaHeight: CGFloat = if model.searchText.isEmpty {
			0
		} else if model.displayedResults.isEmpty {
			Self.emptyResultHeight
		} else {
			CGFloat(min(model.displayedResults.count, Self.maximumVisibleResults))
				* Self.resultHeight
		}

		var frame = window.frame
		let height = Self.searchHeight + resultAreaHeight
		frame.origin.y += frame.height - height
		frame.size = NSSize(width: Self.width, height: height)
		window.setFrame(frame, display: true, animate: window.isVisible)
	}

	override public func show() {
		model.populate()
		model.updateClientRestriction()
		window.ce_restoreState(for: .channelSpotlight)
		resizeToFitResults()
		installKeyMonitorIfNeeded()
		window.makeKeyAndOrderFront(nil)
	}

	override public func close() {
		window.ce_saveState(for: .channelSpotlight)
		window.close()
	}

	public func windowWillClose(_: Notification) {
		if let keyEventMonitor {
			NSEvent.removeMonitor(keyEventMonitor)
		}
		keyEventMonitor = nil
		notifications.cancelAll()
		spotlightDelegate?.channelSpotlightControllerWillClose(self)
	}
}
