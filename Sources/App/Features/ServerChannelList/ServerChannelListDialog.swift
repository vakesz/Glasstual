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
import SwiftUI

@MainActor
public protocol ServerChannelListDialogDelegate: AnyObject {
	func serverChannelListDialogOnUpdate(_ sender: ServerChannelListDialog)
	func serverChannelListDialog(_ sender: ServerChannelListDialog, joinChannels channels: [String])
	func serverChannelDialogWillClose(_ sender: ServerChannelListDialog)
}

@MainActor
public final class ServerChannelListDialog: WindowBase, TDCClientPrototype, NSWindowDelegate {
	private static let initialContentSize = NSSize(width: 720, height: 420)
	private static let minimumContentSize = NSSize(width: 600, height: 320)
	private static let maximumContentSize = NSSize(width: 1024, height: 720)

	var listDelegate: (any ServerChannelListDialogDelegate)? {
		delegate as? any ServerChannelListDialogDelegate
	}

	public private(set) var client: IRCClient!
	public private(set) var clientId: String?
	public var contentAlreadyReceived = false {
		didSet {
			if contentAlreadyReceived {
				model.finishRefresh()
			} else {
				model.isRefreshing = true
			}
		}
	}

	let model = ServerChannelListModel()

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(client:)")
	}

	public init(client: IRCClient) {
		super.init()
		self.client = client
		clientId = client.uniqueIdentifier
		installWindow()
	}

	public var serverSideListArguments: String? {
		model.listArguments(supportedTokens: client.supportInfo.extendedListTokens)
	}

	override public func show() {
		window.ce_restoreState(for: .serverChannelList)
		super.show()
	}

	public func clear() {
		model.clear()
	}

	public func addChannel(_ channel: String, count: UInt, topic: String?) {
		model.enqueue(channelName: channel, memberCount: count, topic: topic)
	}

	private func installWindow() {
		let rootView = ServerChannelListView(
			model: model,
			networkName: client.networkNameAlt,
			supportsMinimumUserCount: client.supportInfo.extendedListSupportsToken("U"),
			joinSelected: { [weak self] in self?.joinSelectedChannels() },
			activate: { [weak self] entryID in self?.activate(entryID) },
			update: { [weak self] in self?.updateList() },
			close: { [weak self] in self?.close() },
			displayedCountChanged: { [weak self] count in self?.updateWindowTitle(count: count) }
		)
		let channelListWindow = NSWindow(
			contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)

		channelListWindow.contentViewController = NSHostingController(rootView: rootView)
		channelListWindow.contentMinSize = Self.minimumContentSize
		channelListWindow.contentMaxSize = Self.maximumContentSize
		channelListWindow.delegate = self
		channelListWindow.isReleasedWhenClosed = false
		channelListWindow.isRestorable = false
		channelListWindow.tabbingMode = .disallowed
		channelListWindow.preventsApplicationTerminationWhenModal = false
		channelListWindow.autorecalculatesKeyViewLoop = true
		window = channelListWindow
		updateWindowTitle(count: 0)
	}

	private func updateWindowTitle(count: Int) {
		window.title = ServerChannelListStrings.windowTitle(publicChannelCount: count)
	}

	private func updateList() {
		model.beginRefresh()
		listDelegate?.serverChannelListDialogOnUpdate(self)
	}

	private func activate(_ entryID: ServerChannelListEntry.ID) {
		model.selectOnly(entryID)
		joinSelectedChannels()
	}

	private func joinSelectedChannels() {
		let channelNames = model.selectedChannelNames
		guard channelNames.isEmpty == false else { return }
		listDelegate?.serverChannelListDialog(self, joinChannels: channelNames)
		model.clearSelection()
	}

	public func windowWillClose(_: Notification) {
		model.cancelPendingWrites()
		window.ce_saveState(for: .serverChannelList)
		listDelegate?.serverChannelDialogWillClose(self)
	}
}
