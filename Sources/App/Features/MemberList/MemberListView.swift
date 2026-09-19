// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// SwiftUI owns the member column and its profile. The native table supplies
/// selection and the pointer hit-testing needed to follow a profile on scroll.
struct MemberListView: View {
	@Bindable var model: MemberList
	let redirectTyping: (String) -> Void
	private let settings = ObservableSettings.shared

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Text(.MemberList.sectionMembers)
					.font(.headline)
				Spacer()
				Button(.MemberList.showProfileAction, systemImage: "info.circle") {
					guard let member = model.selectedProfileMember else { return }
					model.showProfile(for: member.id)
				}
				.labelStyle(.iconOnly)
				.buttonStyle(.borderless)
				.disabled(model.selectedProfileMember == nil)
				.help(Text(.MemberList.showProfileAction))
				.accessibilityIdentifier("member-list-show-profile")
				.popover(isPresented: profileIsPresented, arrowEdge: .leading) {
					if let member = model.profileMember {
						MemberListUserInfoView(content: MemberListUserInfoContent(
							member: member,
							privileges: MemberListRanks.privilegeDescription(for: model.presentationStyle.displayRank(
								isIRCOperator: member.user.isIRCop,
								channelRank: member.rank
							))
						))
					}
				}
			}
			.padding(.horizontal, UISpacing.wide)
			.padding(.vertical, UISpacing.regular)

			MemberListTable(
				model: model,
				revision: model.presentationRevision,
				selection: model.selectedMemberIDs,
				followsProfileOnScroll: settings[SettingsKeys.Appearance.memberListUpdatesPopoverOnScroll],
				redirectTyping: redirectTyping
			)
		}
		.onDisappear { model.hideProfile() }
	}

	private var profileIsPresented: Binding<Bool> {
		Binding(
			get: { model.profileMember != nil },
			set: {
				if $0 == false {
					model.hideProfile()
				}
			}
		)
	}
}
