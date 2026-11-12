// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct MainWindowConnectionPresentation: Equatable {
	let sessionIdentifier: String
	let status: MainWindowConnectionStatus

	init?(session: ServerSession) {
		guard !session.isTerminating, let status = MainWindowConnectionStatus.current(for: session) else { return nil }
		sessionIdentifier = session.uniqueIdentifier
		self.status = status
	}

	enum Action: Equatable {
		case connect, cancelReconnect, disconnect
	}

	var actions: [Action] {
		switch status {
		case .disconnected: [.connect]
		case .waitingToReconnect: [.connect, .cancelReconnect]
		case .connecting, .reconnecting, .loggingOn: [.disconnect]
		case .disconnecting: []
		}
	}

	/// Whether the row has anything to offer. A row with no action would only
	/// say what the toolbar subtitle already says.
	var hasActions: Bool {
		actions.isEmpty == false
	}

	/// The symbol beside the status while nothing is in progress; a connection
	/// in progress shows a spinner instead.
	var symbolName: String {
		switch status {
		case .waitingToReconnect: "clock"
		default: "bolt.slash"
		}
	}

	/// Whether the connection is in progress, which the row marks with a spinner
	/// beside its status.
	var isInProgress: Bool {
		switch status {
		case .connecting, .reconnecting, .loggingOn: true
		default: false
		}
	}

	func perform(_ action: Action, in window: MainWindow?, commands: MenuActionController?) {
		guard let session = window?.selectedSession, let commands,
		      session.uniqueIdentifier == sessionIdentifier,
		      let current = Self(session: session), current.actions.contains(action)
		else { return }
		commands.context.withContext(.sidebarItem(session)) {
			switch action {
			case .connect: commands.connect(nil)
			case .cancelReconnect: commands.cancelReconnection(nil)
			case .disconnect: commands.disconnect(nil)
			}
		}
	}
}

struct MainWindowConnectionRow: View {
	let presentation: MainWindowConnectionPresentation
	let perform: (MainWindowConnectionPresentation.Action) -> Void

	/** The status on the leading edge and its one action on the trailing
	 edge, the way Mail's offline bar says what is wrong and offers the way
	 out. */
	var body: some View {
		HStack(spacing: UISpacing.regular) {
			status
			Spacer(minLength: UISpacing.regular)
			actions
		}
		.controlSize(.small)
		.padding(UISpacing.regular)
		.background(.bar)
		.accessibilityElement(children: .contain)
	}

	@ViewBuilder private var status: some View {
		if presentation.isInProgress {
			HStack(spacing: UISpacing.tight) {
				ProgressView()
				Text(verbatim: presentation.status.title)
			}
			.foregroundStyle(.secondary)
		} else {
			Label(presentation.status.title, systemImage: presentation.symbolName)
				.foregroundStyle(.secondary)
		}
	}

	private var actions: some View {
		ViewThatFits(in: .horizontal) {
			HStack { buttons }.fixedSize()
			VStack(alignment: .leading) { buttons }
		}
	}

	@ViewBuilder private var buttons: some View {
		if presentation.actions.contains(.connect) {
			Button(presentation.status == .waitingToReconnect
				? String(localized: .MainWindow.connectionConnectNow)
				: String(localized: .MainWindow.connectionConnect)) { perform(.connect) }
		}
		if presentation.actions.contains(.cancelReconnect) {
			Button(String(localized: .MainWindow.connectionCancelReconnect)) { perform(.cancelReconnect) }
		}
		if presentation.actions.contains(.disconnect) {
			Button(String(localized: .MainWindow.connectionStopConnecting)) { perform(.disconnect) }
		}
	}
}
