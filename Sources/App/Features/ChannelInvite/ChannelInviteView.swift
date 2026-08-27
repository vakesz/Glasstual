/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

@MainActor
struct ChannelInviteView: View {
	let content: ChannelInviteContent
	let invite: (String) -> Void
	let cancel: () -> Void

	@Binding private var selectedChannel: String

	init(
		content: ChannelInviteContent,
		selectedChannel: Binding<String>,
		invite: @escaping (String) -> Void,
		cancel: @escaping () -> Void
	) {
		self.content = content
		self.invite = invite
		self.cancel = cancel
		_selectedChannel = selectedChannel
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(verbatim: content.headerTitle)
				.font(.headline)
				.textSelection(.enabled)

			Picker(content.channelPickerLabel, selection: $selectedChannel) {
				ForEach(content.channels, id: \.self) { channel in
					Text(verbatim: channel).tag(channel)
				}
			}
			.pickerStyle(.menu)
			.accessibilityLabel(Text(verbatim: content.channelPickerLabel))

			HStack(spacing: 8) {
				Spacer()

				Button(content.cancelButtonTitle, action: cancel)
					.keyboardShortcut(.cancelAction)

				Button(content.inviteButtonTitle) {
					invite(selectedChannel)
				}
				.keyboardShortcut(.defaultAction)
				.disabled(selectedChannel.isEmpty)
			}
		}
		.padding(20)
		.frame(width: 340)
		.onExitCommand(perform: cancel)
	}
}
