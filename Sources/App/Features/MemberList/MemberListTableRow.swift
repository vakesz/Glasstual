// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/// What a member row draws from the person's server profile.
struct MemberRowProfile {
	var displayName: String?
	var color: ProfileColor?
	var avatar: NSImage?

	init() {}

	init(_ user: User, presentation: ServerProfilePresentation) {
		displayName = presentation.displayName(for: user)
		color = presentation.color(for: user)
		avatar = presentation.avatar(for: user.profile, pixelSize: ServerProfilePresentation.memberListPixelSize)
	}
}

/// The table's stable index space, including unselectable section headings.
enum MemberListTableRow: Identifiable, Equatable {
	enum Identity: Hashable {
		case section(MemberListSectionIdentifier)
		case member(User.ID)
	}

	case section(MemberListSection, count: Int)
	case member(Member)

	var id: Identity {
		switch self {
		case let .section(section, _): .section(section.identifier)
		case let .member(member): .member(member.id)
		}
	}

	var member: Member? {
		guard case let .member(member) = self else { return nil }
		return member
	}

	static func == (lhs: Self, rhs: Self) -> Bool {
		switch (lhs, rhs) {
		case let (.section(left, leftCount), .section(right, rightCount)):
			left == right && leftCount == rightCount
		case let (.member(left), .member(right)):
			left == right && left.user == right.user
		default:
			false
		}
	}

	static func rows(in groups: [MemberListGroup]) -> [Self] {
		groups.flatMap { group in
			[.section(group.section, count: group.members.count)] + group.members.map(Self.member)
		}
	}

	func accessibilityDescription(style: MemberListPresentationStyle, displayName: String? = nil) -> String {
		switch self {
		case let .section(section, count):
			return String(localized: .MemberList.sectionAccessibilityLabel(section.title, count.formatted()))
		case let .member(member):
			let user = member.user
			let rank = style.displayRank(isIRCOperator: user.isIRCop, channelRank: member.rank)
			var phrases = [
				displayName.map { String(localized: .MemberList.userWithDisplayName($0, user.nickname)) }
					?? AccessibilityStrings.userListEntry(for: user.nickname),
				MemberListRanks.privilegeDescription(for: rank),
			]
			if user.isAway {
				phrases.append(String(localized: .MemberList.userIsAway))
			}
			if user.isBot {
				phrases.append(String(localized: .MemberList.userIsABot))
			}
			if let account = user.account, account.isEmpty == false {
				phrases.append(String(localized: .MemberList.loggedInAs(account)))
			}
			return phrases.formatted(.list(type: .and))
		}
	}
}

/// Reused native cells host only their small SwiftUI drawing, never a list.
final class MemberListTableCell: NSTableCellView {
	private var hostingView: NSHostingView<MemberListTableRowContent>?
	private var content: MemberListTableRowContent?
	private var showProfile: (() -> Void)?
	private var activate: (() -> Void)?
	/// Opens the member's context menu, for VoiceOver's and other
	/// Accessibility clients' show-menu action.
	var showMenu: (() -> Bool)?

	override var backgroundStyle: NSView.BackgroundStyle {
		didSet {
			guard var content else { return }
			content.isSelected = backgroundStyle == .emphasized
			hostingView?.rootView = content
		}
	}

	func configure(
		row: MemberListTableRow,
		style: MemberListPresentationStyle,
		avatarSize: CGFloat,
		overrides: NicknameColorOverrides,
		profile: MemberRowProfile = MemberRowProfile(),
		activationName: String,
		showProfile: @escaping () -> Void,
		activate: @escaping () -> Void
	) {
		// The table exports proxy rows, whose children come from these cells.
		// Row-view metadata is not part of that exported accessibility tree.
		setAccessibilityElement(true)
		setAccessibilityRole(.cell)
		setAccessibilityLabel(row.accessibilityDescription(style: style, displayName: profile.displayName))
		setAccessibilityIdentifier(row.member.map { AccessibilityIdentifier.memberRow($0.user.nickname) })
		setAccessibilityChildren([])
		self.showProfile = row.member == nil ? nil : showProfile
		self.activate = row.member == nil ? nil : activate
		/* Show Profile stays first. The second action is what a double click on
		 the row does, which a screen reader has no other way to perform. */
		setAccessibilityCustomActions(row.member == nil ? [] : [
			NSAccessibilityCustomAction(
				name: String(localized: .MemberList.showProfileAction), target: self, selector: #selector(openProfile)
			),
			NSAccessibilityCustomAction(
				name: activationName, target: self, selector: #selector(activateRow)
			),
		])
		let content = MemberListTableRowContent(
			row: row, style: style, avatarSize: avatarSize, overrides: overrides, profile: profile,
			isSelected: backgroundStyle == .emphasized
		)
		self.content = content
		if let hostingView {
			hostingView.rootView = content
		} else {
			let host = NSHostingView(rootView: content)
			host.sizingOptions = []
			host.translatesAutoresizingMaskIntoConstraints = false
			host.setAccessibilityElement(false)
			host.setAccessibilityChildren([])
			addSubview(host)
			NSLayoutConstraint.activate([
				host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UISpacing.snug),
				host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UISpacing.snug),
				host.topAnchor.constraint(equalTo: topAnchor),
				host.bottomAnchor.constraint(equalTo: bottomAnchor),
			])
			hostingView = host
		}
	}

	override func accessibilityPerformShowMenu() -> Bool {
		showMenu?() ?? false
	}

	@objc private func openProfile() -> Bool {
		guard let showProfile else { return false }
		showProfile()
		return true
	}

	@objc private func activateRow() -> Bool {
		guard let activate else { return false }
		activate()
		return true
	}
}

extension UserDoubleClickAction {
	/// What a member-list row's activation action is called: the action the
	/// reader chose for a double click on a member, since that is what it runs.
	var accessibilityActionTitle: String {
		switch self {
		case .whois: String(localized: .MemberList.whoisAction)
		case .startDirectConversation: String(localized: .MemberList.openConversationAction)
		case .insertTextField: String(localized: .MemberList.insertNicknameAction)
		@unknown default: String(localized: .MemberList.openConversationAction)
		}
	}
}

private struct MemberListTableRowContent: View {
	let row: MemberListTableRow
	let style: MemberListPresentationStyle
	let avatarSize: CGFloat
	let overrides: NicknameColorOverrides
	let profile: MemberRowProfile
	var isSelected: Bool

	var body: some View {
		Group {
			switch row {
			case let .section(section, count):
				HStack {
					Text(section.title).font(.caption.weight(.semibold)).lineLimit(1)
					Spacer()
					Text(count, format: .number).font(.caption).monospacedDigit()
				}
				.foregroundStyle(.secondary)
			case let .member(member):
				memberContent(member)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.accessibilityHidden(true)
	}

	private func memberContent(_ member: Member) -> some View {
		let user = member.user
		let rank = style.displayRank(isIRCOperator: user.isIRCop, channelRank: member.rank)
		return HStack(spacing: UISpacing.regular) {
			MemberAvatar(
				nickname: user.nickname,
				size: avatarSize,
				overrides: overrides,
				profileColor: profile.color,
				image: profile.avatar
			)
			.opacity(user.isAway ? 0.5 : 1)
			if let displayName = profile.displayName {
				/* The display name gives way first: the nickname is always drawn. */
				Text(TranscriptIsolate.isolated(displayName))
					.lineLimit(1)
					.truncationMode(.tail)
					.foregroundStyle(primaryColor(isAway: user.isAway))
				Text(TranscriptIsolate.isolated(user.nickname))
					.font(.callout)
					.lineLimit(1)
					.fixedSize()
					.layoutPriority(1)
					.foregroundStyle(Color(nsColor: isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor))
			} else {
				Text(user.nickname)
					.lineLimit(1)
					.truncationMode(.tail)
					.foregroundStyle(primaryColor(isAway: user.isAway))
			}
			if user.isBot {
				// A plain secondary caption, as list rows mark a kind of item.
				Text(.MemberList.botCaption)
					.font(.caption)
					.lineLimit(1)
					.fixedSize()
					.foregroundStyle(Color(nsColor: isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor))
			}
			Spacer(minLength: UISpacing.tight)
			if let symbol = style.symbolName(for: rank) {
				Image(systemName: symbol)
					.imageScale(.small)
					.foregroundStyle(isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : style.color(for: rank))
					.help(MemberListRanks.style(for: rank).privilegeDescription)
			}
		}
	}

	private func primaryColor(isAway: Bool) -> Color {
		Color(nsColor: isSelected ? .alternateSelectedControlTextColor : (isAway ? .secondaryLabelColor : .labelColor))
	}
}
