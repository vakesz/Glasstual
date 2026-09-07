import AppKit
import ApplicationServices
import Foundation

extension AccessibilityDriver {
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
			for window in windows {
				if try named("General", role: kAXStaticTextRole, from: window, deadline: deadline) != nil,
				   try named("Add-ons", role: kAXStaticTextRole, from: window, deadline: deadline) != nil
				{
					result = window
					return true
				}
			}
			return false
		}
		guard let result else { throw HarnessFailure.assertion("Settings window missing") }
		return result
	}

	/// SwiftUI may put a composed label on the row's content. Selection and
	/// context actions belong to the native AXRow, so walk a bounded number of
	/// parents to reach it.
	func nativeRow(containing node: AXUIElement, deadline: Double) throws -> AXUIElement {
		var node = node
		for _ in 0 ..< 8 {
			if try text(node, kAXRoleAttribute, deadline: deadline) == kAXRowRole {
				return node
			}
			guard let parent = try element(value(node, kAXParentAttribute, deadline: deadline)) else { break }
			node = parent
		}
		throw HarnessFailure.assertion("Control has no bounded native AXRow ancestor")
	}

	func selectRow(_ label: String, from parent: AXUIElement) async throws {
		try await wait("select visible fixture row \(label)") { deadline in
			guard let node = try named(label, role: kAXStaticTextRole, from: parent, deadline: deadline)
			else { return false }
			let row = try nativeRow(containing: node, deadline: deadline)
			try set(row, attribute: kAXSelectedAttribute, value: kCFBooleanTrue, deadline: deadline)
			return try value(row, kAXSelectedAttribute, deadline: deadline) as? Bool == true
		}
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
		try await wait("fill identified public input \(identifier)") { deadline in
			guard let field = try identified(identifier, from: parent, deadline: deadline) else { return false }
			try set(field, attribute: kAXFocusedAttribute, value: kCFBooleanTrue, deadline: deadline)
			try set(field, attribute: kAXValueAttribute, value: content as CFString, deadline: deadline)
			return try text(field, kAXValueAttribute, deadline: deadline) == content
		}
		try key(48)
	}

	func selectPreferencePage(_ title: String, in window: AXUIElement) async throws {
		var popup: AXUIElement?
		try await wait("choose plugin preference page") { deadline in
			if let radio = try named(title, role: kAXRadioButtonRole, from: window, deadline: deadline) {
				try press(radio, deadline: deadline)
				return true
			}
			popup = try find(from: window, deadline: deadline) {
				guard try text($0, kAXRoleAttribute, deadline: deadline) == kAXPopUpButtonRole else { return false }
				let labels = [
					"Add-ons",
					"Advanced",
					"Installed Add-ons",
					"Smiley Converter",
					"Identity",
					"Connection",
					"Channels",
					"Media",
					"System",
				]
				return try labels.contains(text($0, kAXDescriptionAttribute, deadline: deadline)) ||
					labels.contains(text($0, kAXTitleAttribute, deadline: deadline)) ||
					labels.contains(text($0, kAXValueAttribute, deadline: deadline))
			}
			guard let popup else { return false }
			try press(popup, deadline: deadline)
			return true
		}
		if let popup {
			try await wait("plugin page in picker menu") { deadline in
				guard let item = try named(title, role: kAXMenuItemRole, from: popup, deadline: deadline)
				else { return false }
				guard try value(item, kAXEnabledAttribute, deadline: deadline) as? Bool == true else { return false }
				try press(item, deadline: deadline)
				return true
			}
		}
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
		guard let sidebar = try identified("server-list", from: window, deadline: deadline) else { return nil }
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
