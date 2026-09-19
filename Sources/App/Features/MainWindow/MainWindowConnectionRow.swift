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

	var body: some View {
		ViewThatFits(in: .horizontal) {
			HStack(spacing: UISpacing.regular) {
				status
				Spacer(minLength: UISpacing.regular)
				actions
			}
			VStack(alignment: .leading, spacing: UISpacing.regular) {
				status
				actions
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(UISpacing.regular)
		.background(.bar)
	}

	private var status: some View {
		HStack(spacing: UISpacing.regular) {
			if [.connecting, .reconnecting, .loggingOn].contains(presentation.status) {
				ProgressView().controlSize(.small)
			}
			Text(presentation.status.title).foregroundStyle(.secondary)
		}
		.fixedSize(horizontal: true, vertical: false)
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
			Button(PromptStrings.Action.cancel) { perform(.disconnect) }
		}
	}
}

enum MainWindowMemberRail {
	/// A narrow window borrows the rail's space without overwriting its saved width or visibility.
	static func effectiveWidth(preferred: CGFloat, available: CGFloat) -> CGFloat? {
		let capacity = available - MainWindowConstants.conversationMinimumWidth - MemberListLayout.handleWidth
		guard capacity >= MemberListLayout.minimumWidth else { return nil }
		return min(capacity, min(MemberListLayout.maximumWidth, max(MemberListLayout.minimumWidth, preferred)))
	}
}
