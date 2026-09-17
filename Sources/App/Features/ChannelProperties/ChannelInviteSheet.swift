// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import SwiftUI

@MainActor
final class ChannelInviteSheet: SheetSession, ClientScoped {
	private(set) var client: Client?
	private(set) var clientId: String?
	private(set) var nicknames: [String] = []

	/// The channel the person chose to invite the nicknames to.
	private let onSelectChannel: (String) -> Void

	init(nicknames: [String], on client: Client, onSelectChannel: @escaping (String) -> Void) {
		self.onSelectChannel = onSelectChannel
		super.init(window: nil)
		self.nicknames = nicknames
		self.client = client
		clientId = client.uniqueIdentifier
	}

	func start(withChannels channels: [String]) {
		guard channels.isEmpty == false else {
			return
		}

		setContent(ChannelInviteView(
			headline: Self.invitationTitle(for: nicknames),
			channels: channels,
			invite: { [weak self] channel in
				self?.invite(to: channel)
			},
			cancel: { [weak self] in
				self?.cancel()
			}
		))
		startSheet()
	}

	/// Reports which channel the person chose, and closes the sheet.
	func invite(to channel: String) {
		onSelectChannel(channel)

		submit()
	}

	/// Who the invitation is for: the one nickname, both of them, or how many
	/// there are once naming them all would be a paragraph.
	static func invitationTitle(for nicknames: [String]) -> String {
		let invitees = switch nicknames.count {
		case 0:
			""
		case 1:
			nicknames[0]
		case 2:
			String(localized: .ChannelProperties.joinsExactlyTwoNicknames(nicknames[0], nicknames[1]))
		default:
			String(localized: .ChannelProperties.inviteeCount(nicknames.count))
		}

		return String(localized: .ChannelProperties.headingAboveTheChannelInvite(invitees))
	}
}

@MainActor
struct ChannelInviteView: View {
	let headline: String
	let channels: [String]
	let invite: (String) -> Void
	let cancel: () -> Void

	/** The channel the picker shows, owned by the view.

	 The sheet used to hold it as a plain property behind a hand-made binding.
	 Nothing observed that property, so choosing a channel never redrew the
	 view and the Invite button could not follow the choice. */
	@State private var selectedChannel: String

	init(
		headline: String,
		channels: [String],
		invite: @escaping (String) -> Void,
		cancel: @escaping () -> Void
	) {
		self.headline = headline
		self.channels = channels
		self.invite = invite
		self.cancel = cancel
		_selectedChannel = State(initialValue: Self.initialSelection(from: channels))
	}

	/// The picker starts on the first channel offered, or on nothing when none is.
	static func initialSelection(from channels: [String]) -> String {
		channels.first ?? ""
	}

	var body: some View {
		VStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 6) {
				Text(.ChannelProperties.windowTitle)
					.font(.title2.weight(.semibold))
				Text(verbatim: headline)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)
					.fixedSize(horizontal: false, vertical: true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding([.horizontal, .top], 20)
			.padding(.bottom, 12)

			Form {
				Section {
					Picker(.ChannelProperties.channelPickerLabel, selection: $selectedChannel) {
						ForEach(channels, id: \.self) { channel in
							Text(verbatim: channel).tag(channel)
						}
					}
					.pickerStyle(.menu)
				}
			}
			.formStyle(.grouped)

			Divider()
			HStack(spacing: 8) {
				Spacer()
				Button(PromptStrings.Action.cancel, action: cancel)
					.keyboardShortcut(.cancelAction)
				Button(.ChannelProperties.inviteButton) {
					invite(selectedChannel)
				}
				.keyboardShortcut(.defaultAction)
				.disabled(selectedChannel.isEmpty)
			}
			.padding(12)
		}
		.frame(minWidth: 380, idealWidth: 420, maxWidth: .infinity)
	}
}
