// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

extension MemberListTableController {
	/// Opening a menu targets the clicked row without changing the selection.
	/// An action may then adopt that target, as the SwiftUI selection menu did.
	func contextMenu(at row: Int) -> NSMenu? {
		guard let clicked = member(at: row) else { return nil }
		let identities = model.selectedMemberIDs.contains(clicked.id) ? model.selectedMemberIDs : [clicked.id]
		let members = rows.compactMap(\.member).filter { identities.contains($0.id) }
		let menu = NSMenu()
		let profile = NSMenuItem(
			title: String(localized: .MemberList.showProfileAction),
			action: #selector(showProfileFromMenu(_:)), keyEquivalent: ""
		)
		profile.target = self
		profile.representedObject = identities.count == 1 ? clicked.id : nil
		profile.isEnabled = identities.count == 1
		profile.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
		menu.autoenablesItems = false
		menu.addItem(profile)
		if let commands = AppServices.delegate.menuController {
			let commandsMenu = MenuContentView.nativeMenu(
				menu: commands.userControlMenu,
				context: MenuTargetContext(coordinator: commands, members: members)
			) { [weak model] in
				model?.selectedMemberIDs = identities
			}
			if commandsMenu.items.isEmpty == false {
				menu.addItem(.separator())
			}
			for item in commandsMenu.items {
				commandsMenu.removeItem(item)
				menu.addItem(item)
			}
		}
		return menu
	}

	@objc private func showProfileFromMenu(_ sender: NSMenuItem) {
		guard let identifier = sender.representedObject as? User.ID else { return }
		model.showProfile(for: identifier)
	}

	func tableView(
		_ tableView: NSTableView,
		validateDrop info: any NSDraggingInfo,
		proposedRow row: Int,
		proposedDropOperation _: NSTableView.DropOperation
	) -> NSDragOperation {
		guard member(at: row) != nil, droppedFiles(from: info.draggingPasteboard).isEmpty == false else { return [] }
		tableView.setDropRow(row, dropOperation: .on)
		return .copy
	}

	func tableView(
		_: NSTableView,
		acceptDrop info: any NSDraggingInfo,
		row: Int,
		dropOperation _: NSTableView.DropOperation
	) -> Bool {
		acceptFiles(droppedFiles(from: info.draggingPasteboard), at: row)
	}

	@discardableResult
	func acceptFiles(_ paths: [String], at row: Int) -> Bool {
		guard paths.isEmpty == false, let member = member(at: row) else { return false }
		sendFiles(paths, member.user.nickname)
		return true
	}

	private func droppedFiles(from pasteboard: NSPasteboard) -> [String] {
		let urls = pasteboard.readObjects(
			forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
		) as? [URL] ?? []
		return urls.filter(\.isFileURL).map(\.path)
	}
}
