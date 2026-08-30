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
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual and/or Codeux Software, nor the names of
 *    its contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@MainActor
private struct RegistryFixture {
	let window: MainWindow
	let fixture = GLTClientEnvironmentFixture()
	let client: IRCClient

	var registry: LogControllerRegistry {
		window.logControllers
	}

	init() {
		window = MainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		client = fixture.world.createClient(with: ClientConfig(), reload: false)
	}

	func makeChannel(named name: String) -> IRCChannel {
		fixture.world.createChannel(
			with: ChannelConfig.seed(withName: name),
			on: client,
			add: true,
			adjust: false,
			reload: false
		)
	}
}

@MainActor
@Suite("Log controller registry")
struct LogControllerRegistryTests {
	@Test("Nothing exists until the registry is asked for it")
	func lookupsStartEmpty() {
		let context = RegistryFixture()

		#expect(context.registry.existingController(for: context.client) == nil)
		#expect(context.client.presentation == nil)
		#expect(context.registry.count == 0)
	}

	@Test("Asking for a controller makes one and installs it on the item")
	func lookupMakesAndInstalls() {
		let context = RegistryFixture()

		let controller = context.registry.controller(for: context.client)

		#expect(context.registry.existingController(for: context.client) === controller)
		#expect(context.client.presentation === controller)
		#expect(context.client.logController === controller)
		#expect(controller.backingView == nil)
	}

	@Test("A backing view is made only when the controller is asked to show one")
	func backingViewIsLazyAndStable() {
		let context = RegistryFixture()
		let controller = context.registry.controller(for: context.client)

		#expect(controller.backingView == nil)

		let first = controller.ensureBackingView()
		let second = controller.ensureBackingView()

		#expect(controller.backingView === first)
		#expect(second === first)
	}

	@Test("Asking twice returns the same controller")
	func lookupIsStable() {
		let context = RegistryFixture()

		let first = context.registry.controller(for: context.client)
		let second = context.registry.controller(for: context.client)

		#expect(first === second)
		#expect(context.registry.count == 1)
	}

	@Test("A controller is found by the identifier of the item it draws")
	func lookupByIdentifier() {
		let context = RegistryFixture()
		let controller = context.registry.controller(for: context.client)

		#expect(
			context.registry.controller(withIdentifier: context.client.uniqueIdentifier) === controller
		)
		#expect(context.registry.controller(withIdentifier: "not-an-item") == nil)
	}

	@Test("A channel gets its own controller, tied to the channel")
	func channelsGetTheirOwnController() {
		let context = RegistryFixture()
		let channel = context.makeChannel(named: "#one")

		let controller = context.registry.controller(for: channel)

		#expect(controller.associatedChannel === channel)
		#expect(controller !== context.registry.controller(for: context.client))
	}

	@Test("Registering a client's tree covers the client and every channel it has")
	func registeringATreeCoversChannels() {
		let context = RegistryFixture()
		let first = context.makeChannel(named: "#one")
		let second = context.makeChannel(named: "#two")

		context.registry.registerTree(of: context.client)

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

	@Test("Forgetting a client's tree drops its channels too")
	func forgettingATreeDropsChannels() {
		let context = RegistryFixture()
		let channel = context.makeChannel(named: "#one")
		context.registry.registerTree(of: context.client)

		context.registry.forgetTree(of: context.client)

		#expect(context.registry.count == 0)
		#expect(channel.presentation == nil)
		#expect(context.client.presentation == nil)
	}

	@Test("A tree item with no window has no view to print into")
	func itemsWithoutAWindowHaveNoPresentation() {
		let fixture = GLTClientEnvironmentFixture()
		let client = fixture.world.createClient(with: ClientConfig(), reload: false)

		#expect(client.presentation == nil)
		#expect(client.logController == nil)
	}
}
