// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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

	init(member: Member, privileges: String) {
		let user = member.user
		let unavailable = String(localized: .MemberList.informationUnavailable)
		let stripsFormatting = SettingsKeys.Messages.removeAllFormatting.value

		nickname = user.nickname
		username = user.username?.nonEmpty ?? unavailable
		address = Self.displayText(user.address?.nonEmpty ?? unavailable, stripsFormatting: stripsFormatting)
		realName = Self.displayText(user.realName?.nonEmpty ?? unavailable, stripsFormatting: stripsFormatting)
		account = user.account?.nonEmpty ?? String(localized: .MemberList.notLoggedIn)
		awayStatus = Self.awayStatus(isAway: user.isAway)
		self.privileges = user.isBot
			? String(localized: .MemberList.privilegesWithCaption(
				privileges,
				String(localized: .MemberList.botCaption)
			))
			: privileges
	}

	/** What the profile's Status row shows.

	 The sentence forms the row reads out ("User is away") have something to
	 attach themselves to; "Away" on its own does not. */
	static func awayStatus(isAway: Bool) -> String {
		isAway
			? String(localized: .MemberList.awayStatusAway)
			: String(localized: .MemberList.awayStatusAvailable)
	}

	private static func displayText(_ value: String, stripsFormatting: Bool) -> AttributedString {
		guard stripsFormatting == false else {
			return AttributedString((value as NSString).stripIRCEffects)
		}
		guard let formatted = (value as NSString).attributedString(
			withIRCFormatting: NSFont.systemFont(ofSize: NSFont.systemFontSize),
			preferredFontColor: nil,
			honorFormattingSetting: false
		) else {
			return AttributedString(value)
		}

		return AttributedString(formatted)
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
				infoRow(String(localized: .MemberList.infoUsername), content.username)
				infoRow(String(localized: .MemberList.infoAddress), content.address)
				infoRow(String(localized: .MemberList.infoRealName), content.realName)
				infoRow(String(localized: .MemberList.infoAccount), content.account)
				infoRow(String(localized: .MemberList.infoPrivileges), content.privileges)
				infoRow(String(localized: .MemberList.infoStatus), content.awayStatus)
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

/** The member profile, packaged for an AppKit popover.

 The member list presents the same profile through SwiftUI's `.popover`, which
 needs only the view. A transcript click arrives in an `NSTextView` and is
 anchored with an `NSPopover` instead, so the hosting controller and the
 content the view wants are assembled here rather than in the transcript: what
 a profile is made of stays with the member list. */
enum MemberListUserInfoPopover {
	static func makeViewController(for member: Member) -> NSViewController {
		NSHostingController(
			rootView: MemberListUserInfoView(
				content: MemberListUserInfoContent(
					member: member,
					privileges: MemberListRanks.privilegeDescription(for: member)
				)
			)
		)
	}
}
