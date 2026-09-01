/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import SwiftUI

@MainActor
public protocol AddressBookSheetDelegate: AnyObject {
	func addressBookSheet(_ sender: AddressBookSheet, onOk entry: AddressBookEntry)
	func addressBookSheetWillClose(_ sender: AddressBookSheet)
}

@MainActor
public final class AddressBookSheet: SheetBase, NSWindowDelegate {
	private static let ignoreContentSize = NSSize(width: 620, height: 540)
	private static let trackingContentSize = NSSize(width: 520, height: 390)

	let model: AddressBookEntryModel

	public init(entryType: IRCAddressBookEntryType) {
		model = AddressBookEntryModel(entryType: entryType)
		super.init(window: nil)
		installSheet()
	}

	public init(config: AddressBookEntry) {
		model = AddressBookEntryModel(entry: config)
		super.init(window: nil)
		installSheet()
	}

	private var entryDelegate: (any AddressBookSheetDelegate)? {
		delegate as? any AddressBookSheetDelegate
	}

	private func installSheet() {
		let rootView = AddressBookEntryView(
			model: model,
			submit: { [weak self] in self?.ok(nil) },
			cancel: { [weak self] in self?.cancel(nil) }
		)
		let contentSize = model.entryType == .userTracking
			? Self.trackingContentSize
			: Self.ignoreContentSize
		let hostedSheet = NSWindow(
			contentRect: NSRect(origin: .zero, size: contentSize),
			styleMask: [.titled, .resizable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)

		hostedSheet.contentViewController = NSHostingController(rootView: rootView)
		hostedSheet.contentMinSize = model.entryType == .userTracking
			? NSSize(width: 460, height: 320)
			: NSSize(width: 560, height: 440)
		hostedSheet.delegate = self
		hostedSheet.isReleasedWhenClosed = false
		hostedSheet.isRestorable = false
		hostedSheet.tabbingMode = .disallowed
		hostedSheet.preventsApplicationTerminationWhenModal = false
		hostedSheet.autorecalculatesKeyViewLoop = true
		hostedSheet.title = model.title
		sheet = hostedSheet
	}

	public func start() {
		startSheet()
	}

	override public func ok(_ sender: Any?) {
		guard let entry = model.validatedEntry() else { return }

		entryDelegate?.addressBookSheet(self, onOk: entry)
		super.ok(sender)
	}

	public func okOrError() -> Bool {
		model.validatedEntry() != nil
	}

	public func windowWillClose(_: Notification) {
		entryDelegate?.addressBookSheetWillClose(self)
	}
}
