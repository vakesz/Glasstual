import AppKit
import ApplicationServices
import Foundation

/** Every Accessibility call the harness makes, addressed to one process by pid.

 Elements are found by accessibility identifier only. Everything the harness
 does is an Accessibility action or attribute (AXPress, AXConfirm, AXShowMenu,
 AXSelected, AXFocused, AXValue): it posts no key or mouse events, so no step
 needs the application to have the keyboard, and another application coming
 forward during a run cannot redirect anything.

 Each round trip is timed. Once ``armResponsiveness()`` has been called, the
 slowest one is the scenario's responsiveness measurement: an application that
 cannot answer Accessibility within ``responsivenessLimit`` is not responsive,
 whatever the scenario was waiting for at the time. */
final class AXDriver {
	/// How long the application may take to answer one Accessibility request.
	static let responsivenessLimit = Duration.seconds(2)
	/// The longest one request may block the harness. Longer than the limit, so
	/// a slow answer is measured rather than cut off.
	private static let messagingTimeout: Float = 3

	let pid: pid_t
	let application: AXUIElement
	let signal = ChangeSignal()
	private let isAlive: () -> Bool
	private var observer: AXObserver?

	/// Whether round trips count towards the responsiveness measurement.
	private var measuring = false
	private(set) var slowestRoundTrip = Duration.zero
	private(set) var slowestStep = "none"
	private(set) var roundTrips = 0
	/// What the scenario is waiting for, for the measurement and for failures.
	var currentStep = "launch"

	init(pid: pid_t, isAlive: @escaping () -> Bool) {
		self.pid = pid
		self.isAlive = isAlive
		application = AXUIElementCreateApplication(pid)
		AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
	}

	/// Starts counting round trips towards responsiveness, once the application
	/// has put up its first window: a cold launch is not a stall.
	func armResponsiveness() {
		measuring = true
	}

	/// Fails when any measured round trip took longer than the limit.
	func assertResponsive() throws {
		guard slowestRoundTrip <= Self.responsivenessLimit else {
			throw HarnessFailure.assertion(String(
				format: "Accessibility round trip took %.2fs (limit %.1fs) while waiting for: %@",
				slowestRoundTrip.inSeconds, Self.responsivenessLimit.inSeconds, slowestStep
			))
		}
	}

	// MARK: - Notifications

	/// Wakes waits early on the notifications that mean the window structure or
	/// a value changed. Polling still bounds every wait.
	func observeChanges() {
		var created: AXObserver?
		let callback: AXObserverCallback = { _, _, _, context in
			guard let context else { return }
			Unmanaged<ChangeSignal>.fromOpaque(context).takeUnretainedValue().notify()
		}
		guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
		let context = Unmanaged.passUnretained(signal).toOpaque()
		for notification in [
			kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification,
			kAXValueChangedNotification, kAXUIElementDestroyedNotification, kAXSheetCreatedNotification,
			kAXSelectedRowsChangedNotification, kAXTitleChangedNotification, kAXMenuOpenedNotification,
		] {
			AXObserverAddNotification(created, application, notification as CFString, context)
		}
		CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
		observer = created
	}

	func stopObserving() {
		if let observer {
			CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
		}
		observer = nil
	}

	// MARK: - Waiting

	/// `until`, woken by this application's notifications and recorded as the
	/// current step.
	func until<Value>(
		_ description: String,
		timeout: Duration = .seconds(20),
		_ probe: () throws -> Value?
	) async throws -> Value {
		currentStep = description
		return try await Wait.until(description, timeout: timeout, signal: signal) {
			try checkAlive()
			return try probe()
		}
	}

	func until(_ description: String, timeout: Duration = .seconds(20), _ condition: () throws -> Bool) async throws {
		_ = try await until(description, timeout: timeout) { try condition() ? true : nil }
	}

	private func checkAlive() throws {
		guard isAlive() else {
			throw HarnessFailure.assertion("The application exited while waiting for: \(currentStep)")
		}
	}

	// MARK: - Attributes

	/** One timed attribute read. A busy application is transient: the wait
	 asks again. Anything else that is not a value, such as an attribute the
	 element does not have or an element that went away during a walk, reads as
	 `nil`, so one odd element never aborts a search of the rest. */
	func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
		var value: CFTypeRef?
		let status = timed { AXUIElementCopyAttributeValue(element, name as CFString, &value) }
		switch status {
		case .success: return value
		case .cannotComplete: throw TransientAXError(code: status.rawValue)
		default: return nil
		}
	}

	func string(_ element: AXUIElement, _ name: String) throws -> String? {
		try attribute(element, name) as? String
	}

	func identifier(_ element: AXUIElement) throws -> String? {
		try string(element, kAXIdentifierAttribute)
	}

	func role(_ element: AXUIElement) throws -> String? {
		try string(element, kAXRoleAttribute)
	}

	func value(_ element: AXUIElement) throws -> String? {
		try string(element, kAXValueAttribute)
	}

	func bool(_ element: AXUIElement, _ name: String) throws -> Bool? {
		try (attribute(element, name) as? NSNumber)?.boolValue
	}

	func number(_ element: AXUIElement, _ name: String = kAXValueAttribute) throws -> Int? {
		try (attribute(element, name) as? NSNumber)?.intValue
	}

	func isEnabled(_ element: AXUIElement) throws -> Bool {
		try bool(element, kAXEnabledAttribute) == true
	}

	func children(_ element: AXUIElement) throws -> [AXUIElement] {
		try attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
	}

	func windows() throws -> [AXUIElement] {
		try attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
	}

	/// The element's frame in screen points, top-left origin.
	func frame(_ element: AXUIElement) throws -> CGRect? {
		guard let position = try attribute(element, kAXPositionAttribute),
		      let size = try attribute(element, kAXSizeAttribute),
		      CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
		else { return nil }
		var origin = CGPoint.zero
		var extent = CGSize.zero
		guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
		      AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent)
		else { return nil }
		return CGRect(origin: origin, size: extent)
	}

	// MARK: - Finding elements

	/// The roles whose descendants a search does not enter unless it starts
	/// inside one: their rows can number in the thousands.
	private static let collections: Set<String> = [
		kAXTableRole, kAXOutlineRole, kAXListRole, kAXMenuBarRole, kAXBrowserRole,
	]

	/// What a search reads of every element it passes.
	struct ElementSummary {
		let role: String?
		let identifier: String?
		let children: [AXUIElement]
	}

	/** An element's role, identifier and children in one round trip. A search
	 reads all three of every element it passes, and a busy application answers
	 each request only between pieces of its own main-thread work, so three
	 requests per element made every search three times as slow as it had to be. */
	func summary(_ element: AXUIElement) throws -> ElementSummary {
		var values: CFArray?
		let names = [kAXRoleAttribute, kAXIdentifierAttribute, kAXChildrenAttribute] as CFArray
		let status = timed {
			AXUIElementCopyMultipleAttributeValues(element, names, AXCopyMultipleAttributeOptions(), &values)
		}
		switch status {
		case .success: break
		case .cannotComplete: throw TransientAXError(code: status.rawValue)
		default: return ElementSummary(role: nil, identifier: nil, children: [])
		}
		/* An attribute the element lacks comes back as an error value in its
		 slot, which none of these casts accept. */
		let slots = values as? [AnyObject] ?? []
		let slot = { (index: Int) in index < slots.count ? slots[index] : nil }
		return ElementSummary(
			role: slot(0) as? String,
			identifier: slot(1) as? String,
			children: slot(2) as? [AXUIElement] ?? []
		)
	}

	/** The first element below `root` (or `root` itself) whose identifier is
	 `identifier`, breadth first. Rows of tables, outlines and lists and the
	 menu bar are only searched when the search starts inside them. */
	func find(_ identifier: String, in root: AXUIElement? = nil, limit: Int = 4000) throws -> AXUIElement? {
		try first(in: root ?? application, limit: limit) { $0.identifier == identifier }
	}

	/// Every element below `root`, rows included, whose identifier has `prefix`.
	func all(withPrefix prefix: String, in root: AXUIElement, limit: Int = 4000) throws -> [(String, AXUIElement)] {
		var found: [(String, AXUIElement)] = []
		var queue = [root]
		var index = 0
		while index < queue.count, index < limit {
			let element = queue[index]
			index += 1
			let summary = try summary(element)
			if let identifier = summary.identifier, identifier.hasPrefix(prefix) {
				found.append((identifier, element))
			}
			queue.append(contentsOf: summary.children)
		}
		return found
	}

	/// Every element below `root` whose role is `role`, breadth first, without
	/// walking into the matches themselves.
	func all(role: String, in root: AXUIElement, limit: Int = 400) throws -> [AXUIElement] {
		var found: [AXUIElement] = []
		var queue = try children(root)
		var index = 0
		while index < queue.count, index < limit {
			let element = queue[index]
			index += 1
			let summary = try summary(element)
			if summary.role == role {
				found.append(element)
			} else {
				queue.append(contentsOf: summary.children)
			}
		}
		return found
	}

	private func first(
		in root: AXUIElement,
		limit: Int,
		where matches: (ElementSummary) -> Bool
	) throws -> AXUIElement? {
		var queue = [root]
		var index = 0
		while index < queue.count, index < limit {
			let element = queue[index]
			index += 1
			let summary = try summary(element)
			if matches(summary) {
				return element
			}
			if index > 1, let role = summary.role, Self.collections.contains(role) {
				continue
			}
			queue.append(contentsOf: summary.children)
		}
		return nil
	}

	/// The application window that is, or holds, `identifier`. A SwiftUI
	/// scene's identifier is on a view a few levels inside the window, so the
	/// search of each window is short.
	func window(_ identifier: String) throws -> AXUIElement? {
		let windows = try windows()
		if let window = try windows.first(where: { try self.identifier($0) == identifier }) {
			return window
		}
		for window in windows where try find(identifier, in: window, limit: 120) != nil {
			return window
		}
		return nil
	}

	/// The last `length` characters of a text element's value, read without
	/// copying the whole value across.
	func tail(of element: AXUIElement, length: Int) throws -> String? {
		guard let count = try number(element, kAXNumberOfCharactersAttribute), count > length else { return try value(element) }
		var range = CFRange(location: count - length, length: length)
		guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
		var result: CFTypeRef?
		let status = timed {
			AXUIElementCopyParameterizedAttributeValue(
				element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &result
			)
		}
		switch status {
		case .success: return result as? String
		case .cannotComplete: throw TransientAXError(code: status.rawValue)
		default: return nil
		}
	}

	/// `identifier` inside the window identified by `window`.
	func element(_ identifier: String, inWindow window: String) throws -> AXUIElement? {
		guard let container = try self.window(window) else { return nil }
		return try find(identifier, in: container)
	}

	/** The row of `collection` that holds an element identified `identifier`.
	 Selection and the context menu belong to the native row, and SwiftUI does not
	 reliably publish a cell's parent, so the walk carries the row down with it. */
	func row(containing identifier: String, in collection: AXUIElement, limit: Int = 6000) throws -> AXUIElement? {
		var queue: [(AXUIElement, AXUIElement?)] = [(collection, nil)]
		var index = 0
		while index < queue.count, index < limit {
			let (element, enclosing) = queue[index]
			index += 1
			let summary = try summary(element)
			let row = summary.role == kAXRowRole ? element : enclosing
			if let row, summary.identifier == identifier {
				return row
			}
			queue.append(contentsOf: summary.children.map { ($0, row) })
		}
		return nil
	}

	/// The main-menu item for `command`, wherever it hangs. Never opens a menu.
	func menuItem(_ command: String) throws -> AXUIElement? {
		guard let bar = try attribute(application, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID()
		else { return nil }
		return try find(AXID.menu(command), in: unsafeDowncast(bar, to: AXUIElement.self))
	}

	/// The open context menu of `view`. AppKit lists a context menu as a child
	/// of the view it was popped up in, not of the application.
	func contextMenu(of view: AXUIElement) throws -> AXUIElement? {
		try children(view).first { try role($0) == kAXMenuRole }
	}

	/// The item for `command` in `view`'s open context menu.
	func contextMenuItem(_ command: String, of view: AXUIElement) throws -> AXUIElement? {
		guard let menu = try contextMenu(of: view) else { return nil }
		return try find(AXID.menu(command), in: menu)
	}

	// MARK: - Actions

	/** Performs `action` on `element`. A reply that says the element went
	 away during the request is transient: the action may or may not have
	 landed, and the caller's wait decides by looking again. */
	func perform(_ action: String, on element: AXUIElement) throws {
		let status = timed { AXUIElementPerformAction(element, action as CFString) }
		switch status {
		case .success: return
		case .cannotComplete, .invalidUIElement, .attributeUnsupported, .failure:
			throw TransientAXError(code: status.rawValue)
		default: throw HarnessFailure.assertion("\(action) was refused (AXError \(status.rawValue)) at: \(currentStep)")
		}
	}

	func press(_ element: AXUIElement) throws {
		try perform(kAXPressAction, on: element)
	}

	/** Opens `element`'s context menu. AppKit runs a context menu's tracking
	 loop inside the request, so the request does not return until the menu
	 closes: it is sent with a short timeout, not measured, and a timeout means
	 the menu is open. The caller then waits for the item it wants. */
	func showMenu(_ element: AXUIElement, action: String = kAXShowMenuAction) throws {
		AXUIElementSetMessagingTimeout(element, 0.5)
		let status = AXUIElementPerformAction(element, action as CFString)
		guard status == .success || status == .cannotComplete else {
			throw HarnessFailure.assertion("\(action) was refused (AXError \(status.rawValue)) at: \(currentStep)")
		}
	}

	func set(_ element: AXUIElement, _ attribute: String, to value: CFTypeRef) throws {
		let status = timed { AXUIElementSetAttributeValue(element, attribute as CFString, value) }
		switch status {
		case .success: return
		case .cannotComplete, .invalidUIElement, .failure: throw TransientAXError(code: status.rawValue)
		default:
			throw HarnessFailure.assertion("Setting \(attribute) was refused (AXError \(status.rawValue)) at: \(currentStep)")
		}
	}

	/** Presses the main-menu item for `command` once it is enabled. Returns
	 when the press was delivered.

	 AppKit validates a menu's items only when the menu opens, so an item's
	 enabled state can be stale when nobody has opened its menu since the state
	 changed. When the item reads disabled, its menu is opened and closed once
	 to validate it, then read again. */
	@discardableResult
	func menu(_ command: String, timeout: Duration = .seconds(20)) async throws -> ContinuousClock.Instant {
		let item = try await enabledMenuItem(command, timeout: timeout)
		return try await until("press menu item \(command)", timeout: timeout) {
			let pressed = ContinuousClock.now
			try press(item)
			return pressed
		}
	}

	/// Waits until the main-menu item for `command` is there and enabled,
	/// validating its menu the way ``menu(_:timeout:)`` does, without pressing it.
	func enabledMenuItem(_ command: String, timeout: Duration = .seconds(20)) async throws -> AXUIElement {
		var validatedAt: ContinuousClock.Instant?
		return try await until("enabled menu item \(command)", timeout: timeout) {
			guard let item = try menuItem(command) else { return nil }
			guard try isEnabled(item) else {
				if validatedAt.map({ ContinuousClock.now - $0 > .seconds(1) }) ?? true {
					try validateMenu(containing: command)
					validatedAt = .now
				}
				return nil
			}
			return item
		}
	}

	/// Opens and closes the top-level menu that holds `command`, which makes
	/// AppKit validate its items.
	private func validateMenu(containing command: String) throws {
		guard let bar = try attribute(application, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID()
		else { return }
		for title in try children(unsafeDowncast(bar, to: AXUIElement.self)) where try find(AXID.menu(command), in: title) != nil {
			try showMenu(title, action: kAXPressAction)
			for menu in try children(title) where try role(menu) == kAXMenuRole {
				try perform(kAXCancelAction, on: menu)
			}
			return
		}
	}

	/** Presses the enabled element `lookup` finds. When a press closes the
	 window that holds the element, as an alert's button does, its reply can be
	 lost with the window: a press that was attempted counts once the element
	 is gone, and one that left the element in place is tried again. */
	func press(_ description: String, timeout: Duration = .seconds(20), _ lookup: () throws -> AXUIElement?) async throws {
		var attempted = false
		try await until(description, timeout: timeout) {
			guard let element = try lookup() else { return attempted }
			guard try isEnabled(element) else { return false }
			attempted = true
			try press(element)
			return true
		}
	}

	/// Presses the enabled button `identifier` inside the window `window`.
	func button(_ identifier: String, inWindow window: String, timeout: Duration = .seconds(20)) async throws {
		try await press("enabled button \(identifier)", timeout: timeout) { try element(identifier, inWindow: window) }
	}

	/// Presses the enabled button `identifier` in any window or sheet.
	func button(_ identifier: String, timeout: Duration = .seconds(20)) async throws {
		try await press("enabled button \(identifier)", timeout: timeout) { try anywhere(identifier) }
	}

	/// `identifier` in any of the application's windows, sheets included.
	func anywhere(_ identifier: String) throws -> AXUIElement? {
		for window in try windows() {
			if let match = try find(identifier, in: window) {
				return match
			}
		}
		return nil
	}

	/// Selects the row of `collection` holding `identifier` and waits until the
	/// row reports itself selected.
	func select(_ identifier: String, in collection: @escaping () throws -> AXUIElement?) async throws {
		try await until("select row \(identifier)") {
			guard let container = try collection(), let row = try row(containing: identifier, in: container) else {
				return false
			}
			if try bool(row, kAXSelectedAttribute) != true {
				try set(row, kAXSelectedAttribute, to: kCFBooleanTrue)
			}
			return try bool(row, kAXSelectedAttribute) == true
		}
	}

	/// Sets a checkbox or switch to `on` and waits for the value to read back.
	func toggle(_ identifier: String, inWindow window: String, to on: Bool) async throws {
		try await until("set \(identifier) to \(on)") {
			guard let toggle = try element(identifier, inWindow: window), let value = try number(toggle) else {
				return false
			}
			if value != (on ? 1 : 0) {
				try press(toggle)
			}
			return try number(toggle) == (on ? 1 : 0)
		}
	}

	/** Replaces what a text field holds with `text` through Accessibility,
	 the way dictation and Voice Control enter text: no key events, so the
	 application does not need the keyboard. The field is focused first, which
	 gives it the field editor, so the change reaches its binding as typing
	 would. A secure field's value cannot be read back; the caller checks the
	 effect instead. */
	func fill(
		_ identifier: String,
		with text: String,
		secure: Bool = false,
		in container: @escaping () throws -> AXUIElement?
	) async throws {
		try await until("focus \(identifier)") {
			guard let field = try container().flatMap({ try find(identifier, in: $0) }) else { return false }
			if try bool(field, kAXFocusedAttribute) != true {
				try set(field, kAXFocusedAttribute, to: kCFBooleanTrue)
			}
			return try bool(field, kAXFocusedAttribute) == true
		}
		try await until("\(identifier) holds the new text") {
			guard let field = try container().flatMap({ try find(identifier, in: $0) }) else { return false }
			try set(field, kAXValueAttribute, to: text as CFString)
			return try secure || value(field) == text
		}
	}

	/// `fill` for a field inside the window identified `window`.
	func fill(_ identifier: String, inWindow window: String, with text: String, secure: Bool = false) async throws {
		try await fill(identifier, with: text, secure: secure) { try self.window(window) }
	}

	// MARK: - Diagnostics

	/// A bounded dump of the tree: role, identifier, title and value, one
	/// element per line. Values are cut short; transcripts hold only fixtures.
	/// A busy application can take seconds per answer, so the dump also stops
	/// at `deadline`.
	func dump(limit: Int = 2500, deadline: Duration = .seconds(15)) -> String {
		let end = Deadline(after: deadline)
		var lines: [String] = []
		var stack: [(AXUIElement, Int)] = [(application, 0)]
		while let (element, depth) = stack.popLast(), lines.count < limit {
			guard end.hasPassed == false else {
				lines.append("(cut short after \(Int(deadline.inSeconds))s: the application answered too slowly)")
				break
			}
			let read = { (name: String) -> String in
				var value: CFTypeRef?
				guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else {
					return ""
				}
				let text = (value as? String) ?? (value as? NSNumber)?.stringValue ?? ""
				return String(text.prefix(160)).replacingOccurrences(of: "\n", with: "\\n")
			}
			let role = read(kAXRoleAttribute)
			let identifier = read(kAXIdentifierAttribute)
			lines.append(String(repeating: "  ", count: depth)
				+ "\(role) id=\(identifier) title=\(read(kAXTitleAttribute)) value=\(read(kAXValueAttribute))")
			// The system's file panels list the person's own files.
			guard depth < 40, [AXID.savePanel, AXID.openPanel].contains(identifier) == false else { continue }
			var children: CFTypeRef?
			guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
			      let list = children as? [AXUIElement]
			else { continue }
			stack.append(contentsOf: list.prefix(200).reversed().map { ($0, depth + 1) })
		}
		return lines.joined(separator: "\n") + "\n"
	}

	// MARK: - Measurement

	private func timed(_ call: () -> AXError) -> AXError {
		let start = ContinuousClock.now
		let status = call()
		let elapsed = ContinuousClock.now - start
		roundTrips += 1
		if measuring, elapsed > slowestRoundTrip {
			slowestRoundTrip = elapsed
			slowestStep = currentStep
		}
		return status
	}
}
