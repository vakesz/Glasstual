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

import SwiftUI

@MainActor
public protocol AddressBookSheetDelegate: AnyObject {
	func addressBookSheet(_ sender: AddressBookSheet, onOk entry: AddressBookEntry)
	func addressBookSheetWillClose(_ sender: AddressBookSheet)
}

@MainActor
public final class AddressBookSheet: MainWindowSheetSession {
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
		setContent(rootView)
	}

	public func start() {
		startSheet()
	}

	override public func ok(_ sender: Any?) {
		guard let entry = model.validatedEntry() else { return }

		entryDelegate?.addressBookSheet(self, onOk: entry)
		super.ok(sender)
	}

	override public func sheetDidEnd(withReturnCode _: Int) {
		entryDelegate?.addressBookSheetWillClose(self)
	}
}
