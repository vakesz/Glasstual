/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import GlasstualPluginKit
import SwiftUI

/// What the member list draws that nothing else does. The spacings and the row
/// metrics it shares with the rest of the window are `UISpacing` and
/// `UIListMetrics`; only the avatar and the profile popover are its own.
enum MemberListLayout {
	static let avatarSize: CGFloat = 24
	static let profileAvatarSize: CGFloat = 64
	static let profileLabelWidth: CGFloat = 72
	static let profileWidth: CGFloat = 340
}

struct MemberListView: View {
	@Bindable var model: MemberList
	let redirectTyping: (String) -> Void

	var body: some View {
		List(selection: $model.selectedMemberIDs) {
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
		.overlayScrollers()
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
	/// shows how many people are in it. The title is passed as it is written:
	/// capitalisation belongs to the list style, which knows what the platform
	/// does with a header this year, and uppercasing it here loses the accents
	/// some languages drop on capitals.
	private func sectionHeader(for group: MemberListGroup) -> some View {
		HStack {
			Text(group.section.title)
			Spacer()
			Text(group.members.count, format: .number)
				.monospacedDigit()
				.foregroundStyle(.secondary)
		}
	}

	private func memberRows(_ members: [ChannelUser]) -> some View {
		ForEach(members, id: \.id) { member in
			MemberListRowView(
				model: model,
				member: member,
				overrides: model.nicknameColorOverrides,
				presentationToken: model.presentationRevision
			)
			.tag(member.id)
			.listRowSeparator(.hidden)
		}
	}
}

private struct MemberListRowView: View {
	let model: MemberList
	let member: ChannelUser
	/// Read once for the whole list; see `MemberList.nicknameColorOverrides`.
	let overrides: NicknameColorOverrides?
	/// ChannelUser equality omits user details. Keep the full user as a view input
	/// so rename, account and host changes refresh the row and its open popover too.
	let user: User
	/** What the row draws that its member does not carry: the badge colours, the
	 rank preferences and the appearance behind them. The list bumps one token
	 for all of them, and a row that did not take it as an input would keep the
	 glyph it first drew. */
	let presentationToken: Int

	init(model: MemberList, member: ChannelUser, overrides: NicknameColorOverrides?, presentationToken: Int) {
		self.model = model
		self.member = member
		self.overrides = overrides
		self.presentationToken = presentationToken
		user = member.user
	}

	var body: some View {
		HStack(spacing: UISpacing.regular) {
			MemberAvatar(nickname: user.nickname, size: MemberListLayout.avatarSize, overrides: overrides)
				.opacity(user.isAway ? 0.5 : 1)
				.accessibilityHidden(true)

			HStack(spacing: UISpacing.tight) {
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
					.frame(width: UIListMetrics.glyphWidth)
					/* The glyph stays hidden from assistive technology because the
					 row's own label already names the rank; the tooltip is for the
					 pointer, which has nothing else to read it with. */
					.help(MemberListStrings.privilegeDescription(for: displayRank))
					.accessibilityHidden(true)
			}
		}
		.frame(height: UIListMetrics.rowHeight)
		.contentShape(Rectangle())
		.accessibilityLabel(accessibilityDescription)
		.accessibilityAction(named: MemberListStrings.showProfileAction) {
			model.showProfile(for: member.id)
		}
		/* A plain click opens the profile once the double-click interval has
		 passed without a second click; the double click itself is the list's
		 own primary action and opens the conversation. Both gestures run
		 alongside the list's click rather than instead of it, so selection --
		 Command and Shift clicks included -- stays the list's, and a modified
		 click opens nothing. Hovering used to open the popover after a second,
		 which meant one timer per row and popovers that opened while the
		 pointer was passing through. */
		.simultaneousGesture(TapGesture(count: 2).onEnded {
			model.cancelPendingProfile()
		})
		.simultaneousGesture(TapGesture().onEnded {
			guard clickOffersProfile else { return }
			model.scheduleProfile(for: member.id, after: .seconds(NSEvent.doubleClickInterval))
		})
		.onDisappear {
			model.endProfileInteraction(with: member.id)
		}
		.popover(isPresented: profileIsPresented, arrowEdge: .leading) {
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

	private var profileIsPresented: Binding<Bool> {
		Binding(
			get: { model.memberShowingProfile == member.id },
			set: { isPresented in
				if isPresented {
					model.showProfile(for: member.id)
				} else {
					model.endProfileInteraction(with: member.id)
				}
			}
		)
	}

	/** Whether this click is the kind that offers a profile.

	 Command, Shift, Control and Option all mean something to the list the click
	 also lands in — extend, toggle, context menu — so a modified click is not
	 asking for a profile. `NSApp.currentEvent` is the click being handled, but
	 a gesture replayed outside an event has none, and the live modifier state
	 answers for it rather than a default that lets everything through.
	 VoiceOver gets the profile from the row's action instead: a popover that
	 opened on a timer would move its cursor mid-sentence. */
	private var clickOffersProfile: Bool {
		guard Accessibility.isVoiceOverEnabled == false else { return false }
		let flags = (NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags)
			.intersection(.deviceIndependentFlagsMask)
		return flags.isDisjoint(with: [.command, .shift, .control, .option])
	}

	private var displayRank: UserRank {
		MemberListPresentation.displayRank(for: member)
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
	/** The rank a row stands for.

	 One answer for the glyph, the tooltip, the accessibility label and the
	 profile: with server staff sorted to the top, an IRC operator is drawn as
	 one whatever the channel gave them, and a label that named the channel
	 rank instead disagreed with the glyph beside it. */
	static func displayRank(for member: ChannelUser) -> UserRank {
		/* The shared main-actor store, not a detached read: this is asked once
		 for the glyph, once for the tooltip and once for the accessibility
		 label of every visible row, and each detached read builds its own
		 handle on the defaults suite. */
		if member.user.isIRCop, Preferences.Appearance.memberListSortFavorsServerStaff.value {
			return .irCopByMode
		}
		return member.rank
	}

	static func privilegesDescription(for member: ChannelUser) -> String {
		MemberListStrings.privilegeDescription(for: displayRank(for: member))
	}

	static func symbolName(for rank: UserRank) -> String? {
		switch rank {
		case .irCopByMode: "checkmark.shield.fill"
		case .channelOwner: "crown.fill"
		case .superOperator: "star.fill"
		case .normalOperator: "shield.fill"
		case .halfOperator: "shield.lefthalf.filled"
		case .voiced: "mic.fill"
		/* "Use an x to indicate a user with no mode set", as the preference
		 offers it: a rank column that is blank for most of a channel reads as
		 unfinished to the readers who asked for the mark. */
		default: Preferences.Appearance.memberListNoModeSymbol.value ? "xmark" : nil
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
