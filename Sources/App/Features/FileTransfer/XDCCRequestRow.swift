// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// What one waiting XDCC request says in the File Transfers window.
struct XDCCRequestPresentation: Equatable {
	let title: String
	let filename: String?
	let status: String

	init(request: XDCCRequest) {
		title = switch request.kind {
		case let .pack(pack): String(localized: .FileTransfer.xdccRequestTitle(String(pack), request.bot))
		case .list: String(localized: .FileTransfer.xdccListRequestTitle(request.bot))
		}
		filename = request.filename
		status = switch request.status {
		case .sent: String(localized: .FileTransfer.xdccRequestWaiting)
		case let .queued(position?): String(localized: .FileTransfer.xdccRequestPosition(String(position)))
		case .queued(nil): String(localized: .FileTransfer.xdccRequestQueued)
		case .sending: String(localized: .FileTransfer.xdccRequestSending)
		}
	}
}

/// A request still waiting for its bot, with the way to withdraw it.
struct XDCCRequestRow: View {
	let pending: PendingXDCCRequest
	let cancel: () -> Void

	var body: some View {
		let presentation = XDCCRequestPresentation(request: pending.request)

		HStack(spacing: UISpacing.wide) {
			Image(systemName: "arrow.down.circle.dotted")
				.font(.title2)
				.foregroundStyle(.secondary)
				.frame(width: 44)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: UISpacing.tight) {
				Text(verbatim: presentation.title)
					.lineLimit(1)
				if let filename = presentation.filename {
					Text(verbatim: filename)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
				Text(verbatim: presentation.status)
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Spacer()

			Button(.FileTransfer.cancelRequest, action: cancel)
				.accessibilityIdentifier("xdcc-request-cancel-\(pending.id.uuidString)")
		}
		.padding(.vertical, UISpacing.tight)
		.accessibilityElement(children: .combine)
		.accessibilityAction(named: Text(.FileTransfer.cancelRequest), cancel)
		.accessibilityIdentifier("xdcc-request-row-\(pending.id.uuidString)")
	}
}
