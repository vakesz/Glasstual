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
 *********************************************************************** */

import SwiftUI

@MainActor
struct ChannelInviteView: View {
	let headline: String
	let channels: [String]
	@Binding var selectedChannel: String
	let invite: (String) -> Void
	let cancel: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 6) {
				Text(verbatim: ChannelInviteStrings.windowTitle)
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
					Picker(ChannelInviteStrings.channelPickerLabel, selection: $selectedChannel) {
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
				Button(ChannelInviteStrings.inviteButtonTitle) {
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
