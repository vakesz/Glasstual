// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import SwiftUI

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
				menu: AppServices.delegate.menuController?.userControlMenu
			)
		} primaryAction: { identities in
			guard let identifier = identities.first else { return }
			model.selectedMemberIDs = identities
			model.notePrimaryInteraction(withID: identifier)
			AppServices.delegate.menuController?.memberInMemberListDoubleClicked()
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

	private func memberRows(_ members: [Member]) -> some View {
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
	let member: Member
	/// Read once for the whole list; see `MemberList.nicknameColorOverrides`.
	let overrides: NicknameColorOverrides?
	/// Member equality omits user details. Keep the full user as a view input
	/// so rename, account and host changes refresh the row and its open popover too.
	let user: User
	/// The badge colours and the rank settings behind them, read once for the
	/// whole list. A row that did not take them as an input would keep the glyph
	/// it first drew.
	let style: MemberListPresentationStyle

	init(
		model: MemberList,
		member: Member,
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
					Text(.MemberList.botCaption)
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
					.help(MemberListRanks.style(for: displayRank).privilegeDescription)
					.accessibilityHidden(true)
			}
		}
		.contentShape(Rectangle())
		.accessibilityLabel(accessibilityDescription)
		.accessibilityAction(named: Text(.MemberList.showProfileAction)) {
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
					privileges: MemberListRanks.privilegeDescription(for: displayRank)
				)
			)
		}
		.dropDestination(for: URL.self) { urls, _ in
			let files = urls.filter(\.isFileURL).map(\.path)
			guard files.isEmpty == false else { return false }
			AppServices.delegate.menuController?.sendDroppedFiles(files, nickname: user.nickname)
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
		guard NSWorkspace.shared.isVoiceOverEnabled == false else { return false }
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
			MemberListRanks.privilegeDescription(for: displayRank),
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

private struct MemberListContextMenu: View {
	let model: MemberList
	let identities: Set<User.ID>
	let menu: NSMenu?

	var body: some View {
		if let menu, let coordinator = AppServices.delegate.menuController {
			MenuContentView(
				menu: menu,
				context: MenuTargetContext(coordinator: coordinator, members: clickedMembers)
			) {
				model.selectedMemberIDs = identities
			}
		}
	}

	/// The rows the menu was opened on, so that validation and the command
	/// that follows both answer for what was clicked rather than for the
	/// selection the click is about to replace.
	private var clickedMembers: [Member] {
		model.groups.flatMap(\.members).filter { identities.contains($0.id) }
	}
}
