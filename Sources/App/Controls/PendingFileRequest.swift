// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import SwiftUI

/// Identifies one picker and consumes its completion once. Dismissal keeps the
/// request available because SwiftUI can deliver the result after closing the panel.
struct PendingFileRequest<Kind> {
	struct Request: Identifiable {
		let id = UUID()
		let kind: Kind
	}

	private(set) var request: Request?
	private(set) var isPresented = false

	mutating func present(_ kind: Kind) {
		request = Request(kind: kind)
		isPresented = true
	}

	/// The panel closed with no result. The request outlives it so a completion
	/// arriving afterwards can still be recognised.
	mutating func dismiss(_ id: UUID) {
		guard request?.id == id else { return }
		isPresented = false
	}

	/// Consumes the request when `id` still names it, handing back what it was
	/// for. A stale completion returns `nil` and changes nothing.
	mutating func complete(_ id: UUID) -> Kind? {
		guard let request, request.id == id else { return nil }
		self.request = nil
		isPresented = false
		return request.kind
	}

	/// Drops the request without completing it, for a view that is going away.
	mutating func reset() {
		request = nil
		isPresented = false
	}
}

extension PendingFileRequest where Kind == Void {
	/// A panel that is only ever asked for one thing still needs the identity.
	mutating func present() {
		present(())
	}
}

extension PendingFileRequest {
	/// Binds the panel's presentation to this request alone: a flag lowered for
	/// an older request cannot close the one now on screen.
	static func presentation(_ pending: Binding<Self>) -> Binding<Bool> {
		let requestID = pending.wrappedValue.request?.id
		return Binding(
			get: { pending.wrappedValue.request?.id == requestID && pending.wrappedValue.isPresented },
			set: { isPresented in
				guard isPresented == false, let requestID else { return }
				pending.wrappedValue.dismiss(requestID)
			}
		)
	}
}
