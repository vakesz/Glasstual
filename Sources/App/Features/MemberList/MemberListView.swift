// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// SwiftUI owns the member column and its profile. The native table supplies
/// selection and the pointer hit-testing needed to follow a profile on scroll.
struct MemberListView: View {
	@Bindable var model: MemberList
	let redirectTyping: (String) -> Void
	private let settings = ObservableSettings.shared

	/** Declares the inspector's toolbar, so it reads nothing that changes with
	 membership: a busy channel delivers batches faster than a toolbar should
	 be rebuilt. The table and the profile observe the list in their own views. */
	var body: some View {
		MemberListTableContent(model: model, redirectTyping: redirectTyping)
			/* No title band: an inspector carries its actions in its part of the
			 toolbar. The table's group names the list and counts its members
			 for Accessibility clients. */
			.toolbar {
				ToolbarItem(placement: .automatic) {
					MemberListProfileButton(model: model)
				}
			}
			/* The system's inspector material by default, showing through the
			 table's clear rows. The theme's opaque chrome ground is drawn only when
			 the reader asks the theme to carry the window's chrome. */
			.background {
				if settings[SettingsKeys.Appearance.themesWindowChrome] {
					Rectangle()
						.fill(Color(nsColor: AppServices.theme.chromeBackground))
						.ignoresSafeArea(.container, edges: .top)
				}
			}
			.onDisappear { model.hideProfile() }
	}
}

/// The native table, redrawn for every membership and presentation change.
private struct MemberListTableContent: View {
	let model: MemberList
	let redirectTyping: (String) -> Void
	private let settings = ObservableSettings.shared

	var body: some View {
		MemberListTable(
			model: model,
			revision: model.presentationRevision,
			selection: model.selectedMemberIDs,
			followsProfileOnScroll: settings[SettingsKeys.Appearance.memberListUpdatesPopoverOnScroll],
			redirectTyping: redirectTyping
		)
	}
}

/// Shows the selected member's profile. It reads which member is selected and
/// whether a profile is open, not how either draws.
private struct MemberListProfileButton: View {
	let model: MemberList

	var body: some View {
		Button(.MemberList.showProfileAction, systemImage: "info.circle") {
			guard let member = model.selectedProfileMember else { return }
			model.showProfile(for: member.id)
		}
		.disabled(model.selectedProfileMember == nil)
		.help(Text(.MemberList.showProfileAction))
		.accessibilityIdentifier("member-list-show-profile")
		.popover(isPresented: profileIsPresented, arrowEdge: .bottom) {
			MemberListProfilePopover(model: model)
		}
	}

	private var profileIsPresented: Binding<Bool> {
		Binding(
			get: { model.isShowingProfile },
			set: {
				if $0 == false {
					model.hideProfile()
				}
			}
		)
	}
}

/// The open profile, following the member's changes and the list's
/// presentation.
private struct MemberListProfilePopover: View {
	let model: MemberList

	var body: some View {
		if let member = model.profileMember {
			MemberListUserInfoView(content: MemberListUserInfoContent(
				member: member,
				privileges: MemberListRanks.privilegeDescription(for: model.presentationStyle.displayRank(
					isIRCOperator: member.user.isIRCop,
					channelRank: member.rank
				)),
				profile: MemberRowProfile(member.user, presentation: model.profilePresentation)
			))
		}
	}
}
