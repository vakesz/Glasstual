import AppKit
import ApplicationServices
import Foundation

extension AccessibilityDriver {
	/// The accessibility identifier `SettingsRootView` puts on its sidebar.
	private static let settingsSidebar = "settings-sidebar"

	func window(titled title: String) async throws -> AXUIElement {
		var result: AXUIElement?
		try await wait("fixture window \(title)") { deadline in
			let windows = try value(root, kAXWindowsAttribute, deadline: deadline) as? [AXUIElement] ?? []
			result = try windows.first { try text($0, kAXTitleAttribute, deadline: deadline) == title }
			return result != nil
		}
		guard let result else { throw HarnessFailure.assertion("Required window missing") }
		return result
	}

	func settingsWindow() async throws -> AXUIElement {
		try await menu("Settings\u{2026}", in: "Glasstual")
		var result: AXUIElement?
		try await wait("Settings sidebar") { deadline in
			let windows = try value(root, kAXWindowsAttribute, deadline: deadline) as? [AXUIElement] ?? []
			result = try windows.first { window in
				try identified(Self.settingsSidebar, from: window, deadline: deadline) != nil
			}
			return result != nil
		}
		guard let result else { throw HarnessFailure.assertion("Settings window missing") }
		return result
	}

	/// SwiftUI may put a composed label on the row's content. Selection and
	/// context actions belong to the native AXRow, so walk a bounded number of
	/// parents to reach it.
	func nativeRow(containing node: AXUIElement, deadline: Double) throws -> AXUIElement {
		guard let row = try nativeRowAncestor(containing: node, deadline: deadline)
		else { throw HarnessFailure.assertion("Control has no bounded native AXRow ancestor") }
		return row
	}

	private func nativeRowAncestor(containing node: AXUIElement, deadline: Double) throws -> AXUIElement? {
		var node = node
		for _ in 0 ..< 8 {
			if try text(node, kAXRoleAttribute, deadline: deadline) == kAXRowRole {
				return node
			}
			guard let parent = try element(value(node, kAXParentAttribute, deadline: deadline)) else { break }
			node = parent
		}
		return nil
	}

	/// SwiftUI list descendants do not consistently publish `AXParent`, so a
	/// label-to-parent walk can lose the row. Carry the enclosing row while
	/// traversing down from the native selection container instead.
	private func matchingRow(
		labeled label: String,
		in container: AXUIElement,
		deadline: Double
	) throws -> AXUIElement? {
		var pending: [(element: AXUIElement, row: AXUIElement?)] = [(container, nil)]
		var visited = 0
		while let current = pending.popLast() {
			try HarnessFiles.check(deadline)
			guard !application.isTerminated, visited < 1500 else {
				throw HarnessFailure.assertion("App exited or AX row traversal exceeded node bound")
			}
			visited += 1
			let role = try text(current.element, kAXRoleAttribute, deadline: deadline)
			let enclosingRow = role == kAXRowRole ? current.element : current.row
			let labels = try [
				text(current.element, kAXTitleAttribute, deadline: deadline),
				text(current.element, kAXDescriptionAttribute, deadline: deadline),
				text(current.element, kAXValueAttribute, deadline: deadline),
			]
			if role == kAXStaticTextRole, labels.contains(label), let enclosingRow {
				return enclosingRow
			}
			let children = try value(current.element, kAXChildrenAttribute, deadline: deadline) as? [AXUIElement] ?? []
			pending.append(contentsOf: children.map { ($0, enclosingRow) })
		}
		return nil
	}

	func selectRow(_ label: String, from parent: AXUIElement) async throws {
		var container: AXUIElement?
		try await wait("fixture selection container") { deadline in
			container = try find(from: parent, deadline: deadline) { node in
				let role = try text(node, kAXRoleAttribute, deadline: deadline)
				return [kAXOutlineRole, kAXListRole, kAXTableRole].contains(role)
			}
			return container != nil
		}
		guard let container else { throw HarnessFailure.assertion("Selectable container missing") }

		var row: AXUIElement?
		try await wait("select visible fixture row \(label)") { deadline in
			row = try matchingRow(labeled: label, in: container, deadline: deadline)
			guard let row else { return false }
			try arm(row, deadline: deadline)
			var actions: CFArray?
			let copied = AXUIElementCopyActionNames(row, &actions)
			try HarnessFiles.check(deadline)
			if copied == .success, (actions as? [String])?.contains(kAXPressAction) == true {
				try press(row, deadline: deadline)
			} else {
				try set(row, attribute: kAXSelectedAttribute, value: kCFBooleanTrue, deadline: deadline)
			}
			return try value(row, kAXSelectedAttribute, deadline: deadline) as? Bool == true
		}
	}

	func clickRow(_ label: String, from parent: AXUIElement) async throws {
		try await wait("click visible fixture row \(label)") { deadline in
			guard let container = try find(from: parent, deadline: deadline, matching: { node in
				let role = try text(node, kAXRoleAttribute, deadline: deadline)
				return [kAXOutlineRole, kAXListRole, kAXTableRole].contains(role)
			}) else { return false }
			let row = try matchingRow(labeled: label, in: container, deadline: deadline)
			guard let row else { return false }
			try click(row, deadline: deadline)
			return true
		}
	}

	private func click(_ element: AXUIElement, deadline: Double) throws {
		guard let origin = try point(element, attribute: kAXPositionAttribute, deadline: deadline),
		      let size = try size(element, attribute: kAXSizeAttribute, deadline: deadline)
		else { throw HarnessFailure.assertion("Clickable control has no native frame") }
		let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
		guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
		                         mouseCursorPosition: center, mouseButton: .left),
			let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
			                 mouseCursorPosition: center, mouseButton: .left)
		else { throw HarnessFailure.assertion("Cannot create native pointer event") }
		down.flags = []
		up.flags = []
		down.post(tap: .cghidEventTap)
		up.post(tap: .cghidEventTap)
	}

	private func point(_ element: AXUIElement, attribute: String, deadline: Double) throws -> CGPoint? {
		guard let raw = try value(element, attribute, deadline: deadline),
		      CFGetTypeID(raw) == AXValueGetTypeID()
		else { return nil }
		let value = unsafeDowncast(raw, to: AXValue.self)
		var result = CGPoint.zero
		return AXValueGetValue(value, .cgPoint, &result) ? result : nil
	}

	private func size(_ element: AXUIElement, attribute: String, deadline: Double) throws -> CGSize? {
		guard let raw = try value(element, attribute, deadline: deadline),
		      CFGetTypeID(raw) == AXValueGetTypeID()
		else { return nil }
		let value = unsafeDowncast(raw, to: AXValue.self)
		var result = CGSize.zero
		return AXValueGetValue(value, .cgSize, &result) ? result : nil
	}

	func closeWindow(_ window: AXUIElement) async throws {
		try await wait("close feature window") { deadline in
			guard let close = try element(value(window, kAXCloseButtonAttribute, deadline: deadline))
			else { return false }
			try press(close, deadline: deadline)
			return true
		}
	}

	func toggle(_ label: String, to desired: Bool, from parent: AXUIElement) async throws {
		try await wait("set visible toggle \(label)") { deadline in
			guard let toggle = try named(label, role: kAXCheckBoxRole, from: parent, deadline: deadline),
			      let current = try value(toggle, kAXValueAttribute, deadline: deadline) as? Int else { return false }
			if current != (desired ? 1 : 0) {
				try press(toggle, deadline: deadline)
			}
			return true
		}
		try await wait("toggle value applied") { deadline in
			guard let toggle = try named(label, role: kAXCheckBoxRole, from: parent, deadline: deadline)
			else { return false }
			return try value(toggle, kAXValueAttribute, deadline: deadline) as? Int == (desired ? 1 : 0)
		}
	}

	func fill(_ identifier: String, with content: String, from parent: AXUIElement) async throws {
		var field: AXUIElement?
		try await wait("focus identified public input \(identifier)") { deadline in
			field = try identified(identifier, from: parent, deadline: deadline)
			guard let field else { return false }
			try set(field, attribute: kAXFocusedAttribute, value: kCFBooleanTrue, deadline: deadline)
			return try value(field, kAXFocusedAttribute, deadline: deadline) as? Bool == true
		}
		try key(0, flags: .maskCommand)
		try type(content)
		try await wait("typed identified public input \(identifier)") { deadline in
			guard let field else { return false }
			return try text(field, kAXValueAttribute, deadline: deadline) == content
		}
		try key(48)
	}

	func type(_ content: String) throws {
		guard content.utf8.allSatisfy({ $0 < 128 })
		else { throw HarnessFailure.assertion("Expected ASCII fixture input") }
		for character in content.utf16 {
			guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
			      let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
			else { throw HarnessFailure.assertion("Cannot create keyboard events") }
			[character].withUnsafeBufferPointer {
				down.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
				up.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
			}
			down.postToPid(application.processIdentifier)
			up.postToPid(application.processIdentifier)
		}
	}

	/** The Settings sidebar is one level deep, so every page — the application's
	 own — is a row in the list this identifier names. */
	func selectSettingsPage(_ title: String, in window: AXUIElement) async throws {
		var sidebar: AXUIElement?
		try await wait("Settings sidebar list") { deadline in
			sidebar = try identified(Self.settingsSidebar, from: window, deadline: deadline)
			return sidebar != nil
		}
		guard let sidebar else { throw HarnessFailure.assertion("Settings sidebar missing") }
		try await selectRow(title, from: sidebar)
	}

	func named(_ title: String, role: String, from parent: AXUIElement, deadline: Double) throws -> AXUIElement? {
		try find(from: parent, deadline: deadline) {
			guard try text($0, kAXRoleAttribute, deadline: deadline) == role else { return false }
			if try text($0, kAXTitleAttribute, deadline: deadline) == title ||
				text($0, kAXDescriptionAttribute, deadline: deadline) == title ||
				text($0, kAXValueAttribute, deadline: deadline) == title
			{
				return true
			}
			guard let label = try element(value($0, kAXTitleUIElementAttribute, deadline: deadline))
			else { return false }
			return try text(label, kAXValueAttribute, deadline: deadline) == title
		}
	}

	func button(_ title: String, from parent: AXUIElement) async throws {
		try await wait("enabled fixture UI button \(title)") { deadline in
			guard let button = try named(title, role: kAXButtonRole, from: parent, deadline: deadline),
			      try value(button, kAXEnabledAttribute, deadline: deadline) as? Bool == true else { return false }
			try press(button, deadline: deadline)
			return true
		}
	}

	/// A modal-opening AX press does not return until the modal session ends.
	/// A native click lets the harness drive the panel that the button opens.
	func clickButton(_ title: String, from parent: AXUIElement) async throws {
		try await wait("enabled fixture UI button \(title)") { deadline in
			guard let button = try named(title, role: kAXButtonRole, from: parent, deadline: deadline),
			      try value(button, kAXEnabledAttribute, deadline: deadline) as? Bool == true else { return false }
			try click(button, deadline: deadline)
			return true
		}
	}

	func key(_ code: CGKeyCode, flags: CGEventFlags = []) throws {
		guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
		      let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
		else {
			throw HarnessFailure.assertion("Cannot create native keyboard event")
		}
		down.flags = flags
		up.flags = flags
		down.postToPid(application.processIdentifier)
		up.postToPid(application.processIdentifier)
	}

	func set(_ element: AXUIElement, attribute: String, value: CFTypeRef, deadline: Double) throws {
		try arm(element, deadline: deadline)
		let result = AXUIElementSetAttributeValue(element, attribute as CFString, value)
		try HarnessFiles.check(deadline)
		guard result == .success else { throw HarnessFailure.assertion("Required AX attribute is not settable") }
	}

	func channelRow(_ channel: String, joined: Bool, deadline: Double) throws -> AXUIElement? {
		guard let window = try identified("main-window", from: root, deadline: deadline) else { return nil }
		guard let sidebar = try identified("sidebar", from: window, deadline: deadline) else { return nil }
		let label = "Channel \(channel), Channel " + (joined ? "Joined" : "Not Joined")
		guard let node = try find(from: sidebar, deadline: deadline, matching: {
			let description = try text($0, kAXDescriptionAttribute, deadline: deadline)
			let title = try text($0, kAXTitleAttribute, deadline: deadline)
			return [description, title].contains { $0 == label || $0.hasPrefix(label + ", ") }
		}) else { return nil }
		return try nativeRow(containing: node, deadline: deadline)
	}

	/// Drive a native NSSavePanel/NSOpenPanel sheet to an exact path: Go to Folder
	/// for the directory, then the labeled Save As field when saving.
	func filePanel(_ url: URL, saving: Bool, in parent: AXUIElement) async throws {
		let action = saving ? "Save" : "Open"
		var panel: AXUIElement?
		try await wait("native file panel") { deadline in
			panel = try find(from: parent, deadline: deadline) {
				try text($0, kAXRoleAttribute, deadline: deadline) == kAXSheetRole &&
					named(action, role: kAXButtonRole, from: $0, deadline: deadline) != nil
			}
			return panel != nil
		}
		guard let panel else { throw HarnessFailure.assertion("Native file panel missing") }
		try key(5, flags: [.maskCommand, .maskShift])
		try await wait("Go to Folder path entry") { deadline in
			guard try named("Go", role: kAXButtonRole, from: panel, deadline: deadline) != nil,
			      let field = try element(value(root, kAXFocusedUIElementAttribute, deadline: deadline)),
			      try [kAXTextFieldRole, kAXComboBoxRole].contains(text(field, kAXRoleAttribute, deadline: deadline))
			else { return false }
			let path = saving ? url.deletingLastPathComponent().path : url.path
			try set(field, attribute: kAXValueAttribute, value: path as CFString, deadline: deadline)
			return try text(field, kAXValueAttribute, deadline: deadline) == path
		}
		try await button("Go", from: panel)
		if saving {
			try await wait("Save As synthetic filename") { deadline in
				guard let field = try named("Save As:", role: kAXTextFieldRole, from: panel, deadline: deadline)
				else { return false }
				try set(field, attribute: kAXValueAttribute, value: url.lastPathComponent as CFString,
				        deadline: deadline)
				return try text(field, kAXValueAttribute, deadline: deadline) == url.lastPathComponent
			}
		}
		try await button(action, from: panel)
	}

	func selectChannel(_ channel: String, joined: Bool) async throws {
		try await wait("select fixture sidebar channel") { deadline in
			guard let row = try channelRow(channel, joined: joined, deadline: deadline) else { return false }
			try set(row, attribute: kAXSelectedAttribute, value: kCFBooleanTrue, deadline: deadline)
			return try value(row, kAXSelectedAttribute, deadline: deadline) as? Bool == true
		}
	}

	func contextualJoin(_ channel: String, whileSelected selection: String) async throws {
		try await wait("AXShowMenu on denied channel row") { deadline in
			guard let row = try channelRow(channel, joined: false, deadline: deadline) else { return false }
			try arm(row, deadline: deadline)
			var actions: CFArray?
			let copied = AXUIElementCopyActionNames(row, &actions)
			try HarnessFiles.check(deadline)
			guard copied == .success, (actions as? [String])?.contains(kAXShowMenuAction) == true else {
				throw HarnessFailure
					.assertion("Channel row does not support AXShowMenu; no main-menu fallback is permitted")
			}
			let result = AXUIElementPerformAction(row, kAXShowMenuAction as CFString)
			try HarnessFiles.check(deadline)
			guard result == .success else { throw HarnessFailure.assertion("Native channel AXShowMenu failed") }
			return true
		}
		try await waitForConnectionStatus(connected: true, channel: selection)
		try await wait("Join Channel in native contextual menu") { deadline in
			// Context menus may be app children rather than row children. Never search AXMenuBar descendants.
			let children = try value(root, kAXChildrenAttribute, deadline: deadline) as? [AXUIElement] ?? []
			for child in children {
				guard try text(child, kAXRoleAttribute, deadline: deadline) != kAXMenuBarRole else { continue }
				guard let menu = try find(from: child, deadline: deadline, matching: {
					try text($0, kAXRoleAttribute, deadline: deadline) == kAXMenuRole
				}) else { continue }
				let items = try value(menu, kAXChildrenAttribute, deadline: deadline) as? [AXUIElement] ?? []
				for item in items {
					guard try text(item, kAXRoleAttribute, deadline: deadline) == kAXMenuItemRole,
					      try text(item, kAXTitleAttribute, deadline: deadline) == "Join Channel",
					      try value(item, kAXEnabledAttribute, deadline: deadline) as? Bool == true else { continue }
					try press(item, deadline: deadline)
					return true
				}
			}
			return false
		}
		try HarnessFiles.write("AXShowMenu #retry with #other selected; Join Channel", to: "contextual-join-ax")
	}
}
