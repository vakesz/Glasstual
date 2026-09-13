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

import AppKit
import CocoaExtensions
import SwiftUI

struct MemberListUserInfoContent {
	let nickname: String
	let username: String
	let address: AttributedString
	let realName: AttributedString
	let account: String
	let privileges: String
	let awayStatus: String

	init(member: ChannelUser, privileges: String) {
		let user = member.user
		let unavailable = MemberListStrings.informationUnavailable
		let stripsFormatting = Preferences.Messages.removeAllFormatting.value

		nickname = user.nickname
		username = user.username.nonEmpty ?? unavailable
		address = Self.displayText(user.address.nonEmpty ?? unavailable, stripsFormatting: stripsFormatting)
		realName = Self.displayText(user.realName.nonEmpty ?? unavailable, stripsFormatting: stripsFormatting)
		account = user.account.nonEmpty ?? MemberListStrings.notLoggedIn
		awayStatus = MemberListStrings.awayStatus(isAway: user.isAway)
		self.privileges = user.isBot
			? MemberListStrings.privileges(privileges, caption: MemberListStrings.botCaption)
			: privileges
	}

	private static func displayText(_ value: String, stripsFormatting: Bool) -> AttributedString {
		guard stripsFormatting == false else {
			return AttributedString(value)
		}
		guard let formatted = (value as NSString).attributedString(
			withIRCFormatting: NSFont.systemFont(ofSize: NSFont.systemFontSize),
			preferredFontColor: nil,
			honorFormattingPreference: false
		) else {
			return AttributedString(value)
		}

		return AttributedString(formatted)
	}
}

private extension String? {
	var nonEmpty: String? {
		guard let value = self, value.isEmpty == false else { return nil }
		return value
	}
}

struct MemberListUserInfoView: View {
	let content: MemberListUserInfoContent

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.wide) {
			HStack(spacing: UISpacing.wide) {
				MemberAvatar(nickname: content.nickname, size: MemberListLayout.profileAvatarSize)
					.accessibilityHidden(true)

				Text(content.nickname)
					.font(.title3.weight(.semibold))
					.lineLimit(1)
					.truncationMode(.tail)
			}

			Grid(
				alignment: .leadingFirstTextBaseline,
				horizontalSpacing: UISpacing.regular,
				verticalSpacing: UISpacing.tight
			) {
				infoRow(MemberListStrings.Info.username, content.username)
				infoRow(MemberListStrings.Info.address, content.address)
				infoRow(MemberListStrings.Info.realName, content.realName)
				infoRow(MemberListStrings.Info.account, content.account)
				infoRow(MemberListStrings.Info.privileges, content.privileges)
				infoRow(MemberListStrings.Info.status, content.awayStatus)
			}
		}
		.padding(UISpacing.loose)
		/* A hostmask is routinely longer than any width chosen for it, so the
		 popover has a range rather than a number and the values wrap inside it
		 instead of being cut off where nothing says they were. */
		.frame(
			minWidth: MemberListLayout.profileMinimumWidth,
			idealWidth: MemberListLayout.profileIdealWidth,
			maxWidth: MemberListLayout.profileMaximumWidth,
			alignment: .leading
		)
		.fixedSize(horizontal: false, vertical: true)
		// Everything here is worth pasting into a command or a bug report.
		.textSelection(.enabled)
	}

	private func infoRow(_ label: String, _ value: String) -> some View {
		infoRow(label, AttributedString(value), plainValue: value)
	}

	private func infoRow(
		_ label: String,
		_ value: AttributedString,
		plainValue: String? = nil
	) -> some View {
		GridRow {
			Text(label)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.frame(width: MemberListLayout.profileLabelWidth, alignment: .trailing)
			Text(value)
				.lineLimit(1 ... MemberListLayout.profileValueLineLimit)
				.truncationMode(.tail)
				.help(plainValue ?? String(value.characters))
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
}
