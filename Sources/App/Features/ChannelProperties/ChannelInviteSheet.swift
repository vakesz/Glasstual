/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
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
