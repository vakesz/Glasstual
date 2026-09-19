// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
private struct RegistryFixture {
	let window: MainWindow
	let fixture = ChatEnvironmentFixture()
	let session: ServerSession

	var registry: TranscriptControllerRegistry {
		window.transcriptControllers
	}

	init() {
		window = MainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		session = fixture.chatSession.createSession(with: ServerConfig())
	}

	func makeChannel(named name: String) -> Conversation {
		fixture.chatSession.createConversation(
			with: ConversationConfig.seed(withName: name),
			on: session,
			add: true,
			adjust: false,
			reload: false
		)
	}
}

@MainActor
@Suite("Log controller registry")
struct TranscriptControllerRegistryTests {
	@Test("Nothing exists until the registry is asked for it")
	func lookupsStartEmpty() {
		let context = RegistryFixture()

		#expect(context.registry.existingController(for: context.session) == nil)
		#expect(context.session.presentation == nil)
		#expect(context.registry.count == 0)
	}

	@Test("Asking for a controller makes one and installs it on the item")
	func lookupMakesAndInstalls() {
		let context = RegistryFixture()

		let controller = context.registry.controller(for: context.session)

		#expect(context.registry.existingController(for: context.session) === controller)
		#expect(context.session.presentation === controller)
		#expect(context.session.transcriptController === controller)
		#expect(controller.backingView == nil)
	}

	@Test("A backing view is made only when the controller is asked to show one")
	func backingViewIsLazyAndStable() {
		let context = RegistryFixture()
		let controller = context.registry.controller(for: context.session)

		#expect(controller.backingView == nil)

		let first = controller.ensureBackingView()
		let second = controller.ensureBackingView()

		#expect(controller.backingView === first)
		#expect(second === first)
	}

	@Test("Asking twice returns the same controller")
	func lookupIsStable() {
		let context = RegistryFixture()

		let first = context.registry.controller(for: context.session)
		let second = context.registry.controller(for: context.session)

		#expect(first === second)
		#expect(context.registry.count == 1)
	}

	@Test("A controller is found by the identifier of the item it draws")
	func lookupByIdentifier() {
		let context = RegistryFixture()
		let controller = context.registry.controller(for: context.session)

		#expect(
			context.registry.controller(withIdentifier: context.session.uniqueIdentifier) === controller
		)
		#expect(context.registry.controller(withIdentifier: "not-an-item") == nil)
	}

	@Test("A channel gets its own controller, tied to the channel")
	func channelsGetTheirOwnController() {
		let context = RegistryFixture()
		let channel = context.makeChannel(named: "#one")

		let controller = context.registry.controller(for: channel)

		#expect(controller.associatedConversation === channel)
		#expect(controller !== context.registry.controller(for: context.session))
	}

	@Test("Registering a session covers the session and every channel it has")
	func registeringASidebarCoversChannels() {
		let context = RegistryFixture()
		let first = context.makeChannel(named: "#one")
		let second = context.makeChannel(named: "#two")

		context.registry.registerSidebar(of: context.session)

		#expect(context.registry.count == 3)
		#expect(first.presentation != nil)
		#expect(second.presentation != nil)
	}

	@Test("Forgetting an item drops the entry and clears the item's seam")
	func forgettingClearsBoth() {
		let context = RegistryFixture()
		let channel = context.makeChannel(named: "#one")
		context.registry.controller(for: channel)

		context.registry.forget(channel)

		#expect(context.registry.existingController(for: channel) == nil)
		#expect(channel.presentation == nil)
	}

	@Test("Forgetting a session drops its channels too")
	func forgettingASidebarDropsChannels() {
		let context = RegistryFixture()
		let channel = context.makeChannel(named: "#one")
		context.registry.registerSidebar(of: context.session)

		context.registry.forgetSidebar(of: context.session)

		#expect(context.registry.count == 0)
		#expect(channel.presentation == nil)
		#expect(context.session.presentation == nil)
	}
}
