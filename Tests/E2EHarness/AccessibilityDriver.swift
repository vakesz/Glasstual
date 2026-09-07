import AppKit
import ApplicationServices
import Foundation

@MainActor
struct AccessibilityDriver {
	let application: NSRunningApplication
	let root: AXUIElement
	let artifactPrefix: String

	init(application: NSRunningApplication, artifactPrefix: String = "") {
		self.application = application
		self.artifactPrefix = artifactPrefix
		root = AXUIElementCreateApplication(application.processIdentifier)
	}

	/// Every AX call is bounded by the same absolute deadline: check it, cap the
	/// messaging timeout at the smaller of 500 ms and the remaining time.
	func arm(_ element: AXUIElement, deadline: Double) throws {
		try HarnessFiles.check(deadline)
		AXUIElementSetMessagingTimeout(element, Float(max(0.001, min(0.5, deadline - HarnessFiles.now))))
	}

	/// An AX attribute is `CFTypeRef`; only a value whose type really is
	/// `AXUIElement` may be downcast.
	func element(_ value: CFTypeRef?) -> AXUIElement? {
		guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
		return unsafeDowncast(value, to: AXUIElement.self)
	}

	func value(_ element: AXUIElement, _ attribute: String, deadline: Double) throws -> CFTypeRef? {
		try arm(element, deadline: deadline)
		var result: CFTypeRef?
		let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
		try HarnessFiles.check(deadline)
		if status == .cannotComplete {
			throw HarnessFailure.assertion("AX response exceeded messaging timeout")
		}
		return status == .success ? result : nil
	}

	func text(_ element: AXUIElement, _ attribute: String, deadline: Double) throws -> String {
		try value(element, attribute, deadline: deadline) as? String ?? ""
	}

	func find(from parent: AXUIElement, deadline: Double, excludingContainers: Set<String> = [],
	          matching predicate: (AXUIElement) throws -> Bool) throws -> AXUIElement?
	{
		var pending = [parent]
		var visited = 0
		while let element = pending.popLast() {
			try HarnessFiles.check(deadline)
			guard !application.isTerminated, visited < 1500 else {
				throw HarnessFailure.assertion("App exited or AX traversal exceeded node bound")
			}
			visited += 1
			let matches = try predicate(element)
			try HarnessFiles.check(deadline)
			if matches {
				return element
			}
			if !excludingContainers.isEmpty,
			   try excludingContainers.contains(text(element, kAXRoleAttribute, deadline: deadline))
			{
				continue
			}
			try pending
				.append(contentsOf: value(element, kAXChildrenAttribute, deadline: deadline) as? [AXUIElement] ?? [])
		}
		return nil
	}

	func identified(_ identifier: String, from parent: AXUIElement, deadline: Double) throws -> AXUIElement? {
		let containers: Set = ["main-window", "channel-transcript", "message-input", "server-list"].contains(identifier)
			? [kAXTableRole, kAXOutlineRole, kAXListRole] : []
		return try find(from: parent, deadline: deadline, excludingContainers: containers) {
			try text($0, kAXIdentifierAttribute, deadline: deadline) == identifier
		}
	}

	func wait(_ description: String, deadline: Double? = nil, until condition: (Double) throws -> Bool) async throws {
		try HarnessFiles.write(description, to: artifactPrefix + "last-step.txt")
		let end = deadline ?? HarnessFiles.now + 20
		while HarnessFiles.now < end {
			// One absolute deadline covers traversal, matching, reads and actions, not just tree enumeration.
			let evaluationStart = HarnessFiles.now
			let evaluationEnd = min(end, evaluationStart + 2)
			try HarnessFiles.write(String(evaluationEnd), to: artifactPrefix + "ax-deadline")
			let matched = try condition(evaluationEnd)
			try HarnessFiles.check(evaluationEnd)
			try HarnessFiles.write(
				String(HarnessFiles.now - evaluationStart),
				to: artifactPrefix + "ax-last-latency-seconds"
			)
			try HarnessFiles.check(evaluationEnd)
			try HarnessFiles.remove(artifactPrefix + "ax-deadline")
			if matched {
				return
			}
			try await Task.sleep(for: .milliseconds(100))
		}
		throw HarnessFailure.assertion("Timed out: \(description)")
	}

	func waitForTranscript(_ expected: String, occurrences: Int = 1) async throws {
		try await wait("transcript fixture marker") { deadline in
			guard let window = try identified("main-window", from: root, deadline: deadline),
			      let transcript = try identified("channel-transcript", from: window, deadline: deadline)
			else { return false }
			return try text(transcript, kAXRoleAttribute, deadline: deadline) == kAXTextAreaRole
				&& text(transcript, kAXValueAttribute, deadline: deadline).components(separatedBy: expected)
				.count - 1 >= occurrences
		}
	}

	func typeAndSend(_ message: String) async throws {
		application.activate()
		try await wait("focus empty native message editor") { deadline in
			guard let input = try messageInput(deadline: deadline) else { return false }
			guard try text(input, kAXRoleAttribute, deadline: deadline) == kAXTextAreaRole,
			      try text(input, kAXValueAttribute, deadline: deadline).isEmpty
			else {
				throw HarnessFailure.assertion("Message editor has unexpected role or nonempty input")
			}
			try arm(input, deadline: deadline)
			guard AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
			else {
				throw HarnessFailure.assertion("Cannot focus message editor")
			}
			return try value(input, kAXFocusedAttribute, deadline: deadline) as? Bool == true
		}
		guard message.utf8.allSatisfy({ $0 < 128 })
		else { throw HarnessFailure.assertion("Expected ASCII fixture input") }
		for character in message.utf16 {
			guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
			      let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
			else {
				throw HarnessFailure.assertion("Cannot create keyboard events")
			}
			[character].withUnsafeBufferPointer {
				down.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
				up.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
			}
			down.flags = []
			up.flags = []
			down.postToPid(application.processIdentifier)
			up.postToPid(application.processIdentifier)
		}
		try await wait("typed fixture visible in native editor") { deadline in
			guard let input = try messageInput(deadline: deadline) else { return false }
			return try text(input, kAXValueAttribute, deadline: deadline) == message
		}
		guard let enter = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
		      let release = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false)
		else {
			throw HarnessFailure.assertion("Cannot create Return key events")
		}
		enter.postToPid(application.processIdentifier)
		release.postToPid(application.processIdentifier)
		try await wait("submitted editor clears") { deadline in
			guard let input = try messageInput(deadline: deadline) else { return false }
			return try text(input, kAXValueAttribute, deadline: deadline).isEmpty
		}
	}

	/// Every editor lookup is scoped to the identified main window; a stray text
	/// area elsewhere in the application never satisfies a typing assertion.
	private func messageInput(deadline: Double) throws -> AXUIElement? {
		guard let window = try identified("main-window", from: root, deadline: deadline) else { return nil }
		return try identified("message-input", from: window, deadline: deadline)
	}

	func certificate(answer: Bool?) async throws {
		try await wait("fixture certificate panel") { deadline in
			let windows = try value(root, kAXWindowsAttribute, deadline: deadline) as? [AXUIElement] ?? []
			for window in windows {
				let prompt = try find(from: window, deadline: deadline) { node in
					let value = try text(node, kAXValueAttribute, deadline: deadline)
					let title = try text(node, kAXTitleAttribute, deadline: deadline)
					let expected = "Glasstual can\u{2019}t verify the identity of the server \u{201C}127.0.0.1\u{201D}"
					return value == expected || title == expected
				}
				guard prompt != nil else { continue }
				guard let answer else { return true }
				guard let button = try find(from: window, deadline: deadline, matching: {
					try text($0, kAXRoleAttribute, deadline: deadline) == kAXButtonRole
						&& text($0, kAXTitleAttribute, deadline: deadline) == (answer ? "Continue" : "Cancel")
						&& value($0, kAXEnabledAttribute, deadline: deadline) as? Bool == true
				}) else { return false }
				try press(button, deadline: deadline)
				return true
			}
			return false
		}
	}

	func press(_ element: AXUIElement, deadline: Double) throws {
		try arm(element, deadline: deadline)
		let status = AXUIElementPerformAction(element, kAXPressAction as CFString)
		try HarnessFiles.check(deadline)
		guard status == .success else { throw HarnessFailure.assertion("AX press failed") }
	}

	@discardableResult
	func menu(_ title: String, in menuTitle: String) async throws -> Double {
		application.activate()
		var openedItem: AXUIElement?
		try await wait("open menu \(menuTitle)") { deadline in
			guard let bar = try element(value(root, kAXMenuBarAttribute, deadline: deadline)) else { return false }
			openedItem = try find(from: bar, deadline: deadline) {
				try text($0, kAXRoleAttribute, deadline: deadline) == kAXMenuBarItemRole
					&& text($0, kAXTitleAttribute, deadline: deadline) == menuTitle
			}
			guard let openedItem else { return false }
			try press(openedItem, deadline: deadline)
			return true
		}
		guard let openedItem else { throw HarnessFailure.assertion("Menu did not open") }
		var pressedAt = 0.0
		try await wait("enabled menu item \(title)") { deadline in
			guard let menu = try find(from: openedItem, deadline: deadline, matching: {
				try text($0, kAXRoleAttribute, deadline: deadline) == kAXMenuRole
			}) else { return false }
			// Only direct children of the menu we opened are candidates, not other menus or submenus.
			let items = try value(menu, kAXChildrenAttribute, deadline: deadline) as? [AXUIElement] ?? []
			for item in items {
				guard try text(item, kAXRoleAttribute, deadline: deadline) == kAXMenuItemRole,
				      try text(item, kAXTitleAttribute, deadline: deadline) == title,
				      try value(item, kAXEnabledAttribute, deadline: deadline) as? Bool == true
				else { continue }
				pressedAt = HarnessFiles.now
				if title == "Disconnect" {
					try HarnessFiles.write(String(pressedAt + 5), to: artifactPrefix + "disconnect-deadline")
				}
				if title == "Quit Glasstual" {
					try HarnessFiles.write(String(pressedAt + 5), to: artifactPrefix + "quit-deadline")
				}
				try press(item, deadline: deadline)
				return true
			}
			return false
		}
		return pressedAt
	}

	func waitForConnectionStatus(connected: Bool, deadline: Double? = nil, channel: String? = nil) async throws {
		try await wait(
			connected ? "exact connected title/subtitle" : "disconnected title/subtitle",
			deadline: deadline
		) { end in
			guard let window = try identified("main-window", from: root, deadline: end) else { return false }
			guard try text(window, kAXRoleAttribute, deadline: end) == kAXWindowRole else { return false }
			let title = try text(window, kAXTitleAttribute, deadline: end)
			let separator = " \u{00B7} "
			if let channel {
				let status = connected ? "" : "Disconnected" + separator
				return title.hasPrefix(channel + ", " + status + "E2E" + separator + "e2euser" + separator)
			}
			if connected {
				return title == "E2E, e2euser" + separator + "e2e.local"
			}
			// Teardown clears the selected endpoint and negotiated host, but keeps the configured nickname.
			return title == "E2E, Disconnected" + separator + "e2euser"
		}
	}

	func saveSnapshot() throws {
		let deadline = HarnessFiles.now + 2
		try HarnessFiles.write(String(deadline), to: artifactPrefix + "ax-deadline")
		var lines: [String] = []
		_ = try find(from: root, deadline: deadline, excludingContainers: [
			kAXTableRole,
			kAXOutlineRole,
			kAXListRole,
		]) { node in
			let role = try text(node, kAXRoleAttribute, deadline: deadline)
			let identifier = try text(node, kAXIdentifierAttribute, deadline: deadline)
			let known = ["main-window", "channel-transcript", "message-input", "server-list"]
				.contains(identifier) ? identifier : "other"
			lines.append("\(role) identifier=\(known)")
			return false
		}
		try HarnessFiles.write(lines.joined(separator: "\n"), to: artifactPrefix + "ax-snapshot.txt")
		try HarnessFiles.check(deadline)
		try HarnessFiles.remove(artifactPrefix + "ax-deadline")
	}
}
