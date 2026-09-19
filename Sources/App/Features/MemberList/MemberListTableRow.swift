// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

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

	func accessibilityDescription(style: MemberListPresentationStyle) -> String {
		switch self {
		case let .section(section, count):
			return "\(section.title), \(count.formatted())"
		case let .member(member):
			let user = member.user
			let rank = style.displayRank(isIRCOperator: user.isIRCop, channelRank: member.rank)
			var phrases = [
				AccessibilityStrings.userListEntry(for: user.nickname),
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
		overrides: NicknameColorOverrides,
		showProfile: @escaping () -> Void
	) {
		// The table exports proxy rows, whose children come from these cells.
		// Row-view metadata is not part of that exported accessibility tree.
		setAccessibilityElement(true)
		setAccessibilityRole(.staticText)
		setAccessibilityLabel(row.accessibilityDescription(style: style))
		setAccessibilityChildren([])
		self.showProfile = row.member == nil ? nil : showProfile
		setAccessibilityCustomActions(row.member == nil ? [] : [
			NSAccessibilityCustomAction(
				name: String(localized: .MemberList.showProfileAction), target: self, selector: #selector(openProfile)
			),
		])
		let content = MemberListTableRowContent(
			row: row, style: style, overrides: overrides, isSelected: backgroundStyle == .emphasized
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
				host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
				host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
				host.topAnchor.constraint(equalTo: topAnchor),
				host.bottomAnchor.constraint(equalTo: bottomAnchor),
			])
			hostingView = host
		}
	}

	@objc private func openProfile() -> Bool {
		guard let showProfile else { return false }
		showProfile()
		return true
	}
}

private struct MemberListTableRowContent: View {
	let row: MemberListTableRow
	let style: MemberListPresentationStyle
	let overrides: NicknameColorOverrides
	var isSelected: Bool

	var body: some View {
		Group {
			switch row {
			case let .section(section, count):
				HStack {
					Text(section.title).font(.caption.weight(.semibold))
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
			MemberAvatar(nickname: user.nickname, size: MemberListLayout.avatarSize, overrides: overrides)
				.opacity(user.isAway ? 0.5 : 1)
			Text(user.nickname)
				.lineLimit(1)
				.truncationMode(.tail)
				.foregroundStyle(Color(nsColor: isSelected ? .alternateSelectedControlTextColor :
						(user.isAway ? .secondaryLabelColor : .labelColor)))
			if user.isBot {
				Text(.MemberList.botCaption)
					.font(.caption2.weight(.medium))
					.foregroundStyle(Color(nsColor: isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor))
					.padding(.horizontal, UISpacing.tight)
					.background(.quaternary, in: Capsule())
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
}
