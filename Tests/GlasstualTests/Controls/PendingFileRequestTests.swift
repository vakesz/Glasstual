// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import SwiftUI
import Testing

@MainActor
struct PendingFileRequestTests {
	private final class Store {
		var pending = PendingFileRequest<String>()

		var binding: Binding<PendingFileRequest<String>> {
			Binding(get: { self.pending }, set: { self.pending = $0 })
		}
	}

	@Test("An old picker binding cannot dismiss a replacement request")
	func staleBinding() throws {
		let store = Store()
		store.pending.present("first")
		let first = PendingFileRequest.presentation(store.binding)
		store.pending.present("second")
		let secondID = try #require(store.pending.request?.id)
		let second = PendingFileRequest.presentation(store.binding)

		#expect(first.wrappedValue == false)
		first.wrappedValue = false
		#expect(second.wrappedValue)
		#expect(store.pending.request?.id == secondID)
		#expect(store.pending.isPresented)
	}

	@Test("A binding created without a request cannot dismiss a later picker")
	func idleBinding() {
		let store = Store()
		let idle = PendingFileRequest.presentation(store.binding)
		store.pending.present("new")
		idle.wrappedValue = false
		#expect(idle.wrappedValue == false)
		#expect(store.pending.isPresented)
	}

	@Test("Dismissal retains the matching result until it is consumed once")
	func matchingDismissal() throws {
		let store = Store()
		store.pending.present("current")
		let id = try #require(store.pending.request?.id)
		let presentation = PendingFileRequest.presentation(store.binding)
		#expect(presentation.wrappedValue)
		presentation.wrappedValue = false
		#expect(presentation.wrappedValue == false)
		#expect(store.pending.complete(id) == "current")
		#expect(store.pending.complete(id) == nil)
		presentation.wrappedValue = true
		#expect(presentation.wrappedValue == false)
	}
}
