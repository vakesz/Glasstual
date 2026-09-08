/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import GlasstualPluginKit
import SwiftUI

struct MemberListView: View {
	@Bindable var model: MemberList
	let redirectTyping: (String) -> Void

	var body: some View {
		_ = model.presentationRevision
		return List(selection: $model.selectedMemberIDs) {
			ForEach(model.groups) { group in
				Section {
					memberRows(group.members)
				} header: {
					sectionHeader(for: group)
				}
			}
		}
		/* Inset rows on no ground of their own: the sidebar style brings a
		 material with it, and beside the transcript that read as a second
		 sidebar. The column's background is the caller's, and the divider
		 beside it is the only edge. */
		.listStyle(.inset)
		.scrollContentBackground(.hidden)
		.listSectionSeparator(.hidden)
		.contextMenu(forSelectionType: User.ID.self) { identities in
			MemberListContextMenu(
				model: model,
				identities: identities,
				menu: AppController.shared.menuController?.userControlMenu
			)
		} primaryAction: { identities in
			guard let identifier = identities.first else { return }
			model.selectedMemberIDs = identities
			model.notePrimaryInteraction(withID: identifier)
			AppController.shared.menuController?.memberInMemberListDoubleClicked(model)
		}
		.redirectsPrintableInput(to: redirectTyping)
	}

	/// Rank title on the left, head count on the right, the way Mail counts a
	/// mailbox. Every group gets one, so a channel with a single rank still
	/// shows how many people are in it.
	private func sectionHeader(for group: MemberListGroup) -> some View {
		HStack {
			Text(group.section.title.localizedUppercase)
			Spacer()
			Text(group.members.count, format: .number)
				.monospacedDigit()
				.foregroundStyle(.secondary)
		}
	}

	private func memberRows(_ members: [ChannelUser]) -> some View {
		ForEach(members, id: \.id) { member in
			MemberListRowView(model: model, member: member)
				.tag(member.id)
				.listRowSeparator(.hidden)
		}
	}
}

private struct MemberListRowView: View {
	let model: MemberList
	let member: ChannelUser
	/// ChannelUser equality omits user details. Keep the full user as a view input
	/// so rename, account and host changes refresh the row and its open popover too.
	let user: User

	init(model: MemberList, member: ChannelUser) {
		self.model = model
		self.member = member
		user = member.user
	}

	@State private var showsDetails = false
	@State private var hoverTask: Task<Void, Never>?

	var body: some View {
		HStack(spacing: 8) {
			MemberAvatar(nickname: user.nickname, size: 24)
				.opacity(user.isAway ? 0.5 : 1)
				.accessibilityHidden(true)

			HStack(spacing: 4) {
				Text(user.nickname)
					.lineLimit(1)
					.truncationMode(.tail)
					.foregroundStyle(user.isAway ? .secondary : .primary)

				if user.isBot {
					Text(MemberListStrings.botCaption)
						.font(.caption.weight(.medium))
						.foregroundStyle(.secondary)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)

			if let symbol = MemberListPresentation.symbolName(for: displayRank) {
				Image(systemName: symbol)
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(MemberListPresentation.color(for: displayRank))
					.frame(width: 16)
					.accessibilityHidden(true)
			}
		}
		.frame(height: 28)
		.contentShape(Rectangle())
		.accessibilityLabel(accessibilityDescription)
		.onHover { hovering in
			hoverTask?.cancel()
			hoverTask = nil
			guard hovering, Accessibility.isVoiceOverEnabled == false else {
				showsDetails = false
				return
			}

			hoverTask = Task { @MainActor in
				try? await Task.sleep(for: .seconds(1))
				guard Task.isCancelled == false else { return }
				showsDetails = true
			}
		}
		.onDisappear {
			hoverTask?.cancel()
		}
		.popover(isPresented: $showsDetails, arrowEdge: .leading) {
			MemberListUserInfoView(
				content: MemberListUserInfoContent(
					member: member,
					privileges: MemberListPresentation.privilegesDescription(for: member)
				)
			)
		}
		.dropDestination(for: URL.self) { urls, _ in
			let files = urls.filter(\.isFileURL).map(\.path)
			guard files.isEmpty == false else { return false }
			AppController.shared.menuController?.memberSendDroppedFiles(files, to: user.nickname)
			return true
		}
	}

	private var displayRank: UserRank {
		if Preferences.Appearance.memberListSortFavorsServerStaff.detachedValue, user.isIRCop {
			return .irCopByMode
		}
		return member.rank
	}

	private var accessibilityDescription: String {
		var description = AccessibilityStrings.userListEntry(for: user.nickname)
		description += ", \(MemberListPresentation.privilegesDescription(for: member))"
		if user.isAway {
			description += ", \(MemberListStrings.userIsAway)"
		}
		if user.isBot {
			description += ", \(MemberListStrings.userIsBot)"
		}
		if let account = user.account, account.isEmpty == false {
			description += ", \(MemberListStrings.loggedIn(account: account))"
		}
		return description
	}
}

private struct MemberListContextMenu: View {
	let model: MemberList
	let identities: Set<User.ID>
	let menu: NSMenu?

	var body: some View {
		if let menu, let coordinator = AppController.shared.menuController?.actionCoordinator {
			AppMenuContent(
				menu: menu,
				context: AppMenuContext(coordinator: coordinator, members: clickedMembers)
			) {
				model.selectedMemberIDs = identities
			}
		}
	}

	/// The rows the menu was opened on, so that validation and the command
	/// that follows both answer for what was clicked rather than for the
	/// selection the click is about to replace.
	private var clickedMembers: [ChannelUser] {
		model.groups.flatMap(\.members).filter { identities.contains($0.id) }
	}
}

enum MemberListPresentation {
	static func privilegesDescription(for member: ChannelUser) -> String {
		MemberListStrings.privilegeDescription(for: member.user.isIRCop ? .irCopByMode : member.rank)
	}

	static func symbolName(for rank: UserRank) -> String? {
		switch rank {
		case .irCopByMode: "checkmark.shield.fill"
		case .channelOwner: "crown.fill"
		case .superOperator: "star.fill"
		case .normalOperator: "shield.fill"
		case .halfOperator: "shield.lefthalf.filled"
		case .voiced: "mic.fill"
		default: nil
		}
	}

	static func color(for rank: UserRank) -> Color {
		guard let badge = badge(for: rank) else { return .secondary }
		let color = TextualUserDefaults.container.color(for: badge.preferenceKey)
		return color.alphaComponent > 0 ? Color(nsColor: color) : .secondary
	}

	private static func badge(for rank: UserRank) -> UserListModeBadge? {
		switch rank {
		case .irCopByMode: .ircOperator
		case .channelOwner: .channelOwner
		case .superOperator: .superOperator
		case .normalOperator: .normalOperator
		case .halfOperator: .halfOperator
		case .voiced: .voiced
		default: nil
		}
	}
}
