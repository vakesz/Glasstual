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
		List(selection: $model.selectedMemberIDs) {
			ForEach(model.groups) { group in
				if model.groups.count > 1 {
					Section(group.section.title.localizedUppercase) {
						memberRows(group.members)
					}
				} else {
					memberRows(group.members)
				}
			}
		}
		.listStyle(.sidebar)
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
		.overlay {
			Color.clear
				.id(model.presentationRevision)
				.allowsHitTesting(false)
		}
		.redirectsPrintableInput(to: redirectTyping)
	}

	private func memberRows(_ members: [ChannelUser]) -> some View {
		ForEach(members, id: \.id) { member in
			MemberListRowView(model: model, member: member)
				.tag(member.id)
		}
	}
}

private struct MemberListRowView: View {
	let model: MemberList
	let member: ChannelUser

	@State private var showsDetails = false
	@State private var hoverTask: Task<Void, Never>?

	var body: some View {
		HStack(spacing: 8) {
			MemberAvatar(nickname: member.user.nickname, size: 24)
				.opacity(member.user.isAway ? 0.5 : 1)
				.accessibilityHidden(true)

			HStack(spacing: 4) {
				Text(member.user.nickname)
					.lineLimit(1)
					.truncationMode(.tail)
					.foregroundStyle(member.user.isAway ? .secondary : .primary)

				if member.user.isBot {
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
			AppController.shared.menuController?.memberSendDroppedFiles(files, to: member.user.nickname)
			return true
		}
	}

	private var displayRank: UserRank {
		if Preferences.Appearance.memberListSortFavorsServerStaff.detachedValue, member.user.isIRCop {
			return .irCopByMode
		}
		return member.rank
	}

	private var accessibilityDescription: String {
		var description = AccessibilityStrings.userListEntry(for: member.user.nickname)
		description += ", \(MemberListPresentation.privilegesDescription(for: member))"
		if member.user.isAway {
			description += ", \(MemberListStrings.userIsAway)"
		}
		if member.user.isBot {
			description += ", \(MemberListStrings.userIsBot)"
		}
		if let account = member.user.account, account.isEmpty == false {
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
		if let menu {
			AppMenuContent(menu: menu) {
				model.selectedMemberIDs = identities
			}
		}
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
