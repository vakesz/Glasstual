/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
		awayStatus = user.isAway ? MemberListStrings.userIsAway : MemberListStrings.userIsNotAway
		self.privileges = user.isBot ? "\(privileges) (\(MemberListStrings.botCaption))" : privileges
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
		VStack(alignment: .leading, spacing: 12) {
			HStack(spacing: 12) {
				MemberAvatar(nickname: content.nickname, size: 64)
					.accessibilityHidden(true)

				Text(content.nickname)
					.font(.title3.weight(.semibold))
					.lineLimit(1)
					.truncationMode(.tail)
			}

			Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
				infoRow(MemberListStrings.Info.username, content.username)
				infoRow(MemberListStrings.Info.address, content.address)
				infoRow(MemberListStrings.Info.realName, content.realName)
				infoRow(MemberListStrings.Info.account, content.account)
				infoRow(MemberListStrings.Info.privileges, content.privileges)
				infoRow(MemberListStrings.Info.status, content.awayStatus)
			}
		}
		.padding(16)
		.frame(width: 340, alignment: .leading)
	}

	private func infoRow(_ label: String, _ value: String) -> some View {
		infoRow(label, AttributedString(value))
	}

	private func infoRow(_ label: String, _ value: AttributedString) -> some View {
		GridRow {
			Text(label)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.frame(width: 72, alignment: .trailing)
			Text(value)
				.lineLimit(1)
				.truncationMode(.tail)
		}
	}
}
