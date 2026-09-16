/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Foundation
import GlasstualPluginKit
import SwiftUI

/// What the member list draws that nothing else does. The spacings and the row
/// metrics it shares with the rest of the window are `UISpacing` and
/// `UIListMetrics`; only the avatar and the profile popover are its own.
enum MemberListLayout {
	static let avatarSize: CGFloat = 24
	static let profileAvatarSize: CGFloat = 64
	static let profileLabelWidth: CGFloat = 72
	static let profileMinimumWidth: CGFloat = 280
	static let profileIdealWidth: CGFloat = 340
	static let profileMaximumWidth: CGFloat = 420
	/// How many lines an address or a real name may wrap onto before it is cut.
	/// A hostmask is routinely longer than the popover is wide.
	static let profileValueLineLimit = 3
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
			AppController.shared.menuController?.actionCoordinator.memberInMemberListDoubleClicked(model)
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
				style: model.presentationStyle
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
	/// The badge colours and the rank preferences behind them, read once for the
	/// whole list. A row that did not take them as an input would keep the glyph
	/// it first drew.
	let style: MemberListPresentationStyle

	init(
		model: MemberList,
		member: ChannelUser,
		overrides: NicknameColorOverrides?,
		style: MemberListPresentationStyle
	) {
		self.model = model
		self.member = member
		self.overrides = overrides
		self.style = style
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
						.font(.caption2.weight(.medium))
						.padding(.horizontal, UISpacing.tight)
						.background(.quaternary, in: Capsule())
						.accessibilityHidden(true)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)

			if let symbol = style.symbolName(for: displayRank) {
				Image(systemName: symbol)
					.imageScale(.small)
					.foregroundStyle(style.color(for: displayRank))
					.frame(width: UIListMetrics.glyphWidth)
					/* The glyph stays hidden from assistive technology because the
					 row's own label already names the rank; the tooltip is for the
					 pointer, which has nothing else to read it with. */
					.help(MemberListStrings.privilegeDescription(for: displayRank))
					.accessibilityHidden(true)
			}
		}
		.contentShape(Rectangle())
		.accessibilityLabel(accessibilityDescription)
		.accessibilityAction(named: MemberListStrings.showProfileAction) {
			model.showProfile(for: member.id)
		}
		/* A plain click opens the profile at once; the double click is the
		 list's own primary action, opens the conversation, and takes the
		 first click's popover down. Waiting out the double-click interval
		 before opening made the profile trail the click by however long the
		 reader's Double-click speed is set to. Both gestures run alongside
		 the list's click rather than instead of it, so selection -- Command
		 and Shift clicks included -- stays the list's, and a modified click
		 opens nothing. */
		.simultaneousGesture(TapGesture(count: 2).onEnded {
			model.hideProfile()
		})
		.simultaneousGesture(TapGesture().onEnded {
			guard clickOffersProfile else { return }
			model.showProfile(for: member.id)
		})
		.onDisappear {
			model.endProfileInteraction(with: member.id)
		}
		.popover(isPresented: profileIsPresented, arrowEdge: .leading) {
			MemberListUserInfoView(
				content: MemberListUserInfoContent(
					member: member,
					privileges: MemberListStrings.privilegeDescription(for: displayRank)
				)
			)
		}
		.dropDestination(for: URL.self) { urls, _ in
			let files = urls.filter(\.isFileURL).map(\.path)
			guard files.isEmpty == false else { return false }
			AppController.shared.menuController?.actionCoordinator.sendDroppedFiles(files, nickname: user.nickname)
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
		style.displayRank(isIRCOperator: user.isIRCop, channelRank: member.rank)
	}

	private var accessibilityDescription: String {
		var phrases = [
			AccessibilityStrings.userListEntry(for: user.nickname),
			MemberListStrings.privilegeDescription(for: displayRank),
		]
		if user.isAway {
			phrases.append(MemberListStrings.userIsAway)
		}
		if user.isBot {
			phrases.append(MemberListStrings.userIsBot)
		}
		if let account = user.account, account.isEmpty == false {
			phrases.append(MemberListStrings.loggedIn(account: account))
		}
		return phrases.formatted(.list(type: .and))
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

/// What a member is called outside the list, where there is one member to draw
/// rather than a column of them and no snapshot in hand.
enum MemberListPresentation {
	static func displayRank(for member: ChannelUser) -> UserRank {
		MemberListPresentationStyle.current()
			.displayRank(isIRCOperator: member.user.isIRCop, channelRank: member.rank)
	}

	static func privilegesDescription(for member: ChannelUser) -> String {
		MemberListStrings.privilegeDescription(for: displayRank(for: member))
	}
}
