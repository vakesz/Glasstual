/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

private final class WindowListKeyStub: WindowBase {}

/** The window list keys on the runtime class name. Callers used to spell that
 name as a `"TDC…"` literal, which stopped matching the moment a class gave up
 its Objective-C name: the lookup missed, so the dialog opened a second time
 instead of coming forward. */
@MainActor
@Suite("Window list keys")
struct WindowListKeyTests {
	@Test("A key derived from the class matches the key derived from an instance")
	func classKeyMatchesInstanceKey() {
		let controller = WindowListKeyStub()

		#expect(
			WindowController.windowDescription(forClass: WindowListKeyStub.self)
				== WindowController.windowDescription(for: controller)
		)
	}

	@Test("A related key derived from the class matches the key derived from an instance")
	func relatedClassKeyMatchesInstanceKey() {
		let controller = WindowListKeyStub()
		let identifier = "u-1"

		#expect(
			WindowController.windowDescription(forClass: WindowListKeyStub.self, inRelationTo: identifier)
				== WindowController.windowDescription(for: controller, inRelationTo: identifier)
		)
	}

	@Test("A registered window comes back under the key its class derives")
	func registeredWindowIsFoundByClassKey() {
		let windowController = WindowController()
		let controller = WindowListKeyStub()
		windowController.addWindow(toWindowList: controller)

		let key = WindowController.windowDescription(forClass: WindowListKeyStub.self)
		let found = windowController.window(fromWindowList: key) as? WindowListKeyStub

		#expect(found === controller)

		windowController.removeWindow(fromWindowList: controller)

		#expect(windowController.window(fromWindowList: key) == nil)
	}

	/** Every dialog the app looks up by class. A class that keeps an
	 Objective-C name and one that does not both have to key the same way. */
	@Test("The dialogs the app looks up derive a key from their own class name")
	func lookedUpDialogsDeriveTheirKey() {
		let dialogs: [AnyClass] = [
			PreferencesController.self,
			ChannelPropertiesSheet.self,
			ChannelModifyTopicSheet.self,
			ChannelModifyModesSheet.self,
			ChannelBanListSheet.self,
			ChannelInviteSheet.self,
			ServerChangeNicknameSheet.self,
			ServerHighlightListSheet.self,
			ServerPropertiesSheet.self,
			ServerChannelListDialog.self,
		]

		for dialog in dialogs {
			#expect(WindowController.windowDescription(forClass: dialog) == NSStringFromClass(dialog))
		}
	}
}
