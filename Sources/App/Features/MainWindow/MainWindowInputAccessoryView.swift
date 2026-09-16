/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Observation
import SwiftUI

@MainActor
@Observable
final class MainWindowInputAccessoryModel {
	private(set) var replyMessageIdentifier: String?
	private(set) var replyNickname: String?
	private(set) var replyExcerpt: String?
	private(set) var typingNicknames: [String] = []

	var hasContent: Bool {
		replyMessageIdentifier != nil || typingNicknames.isEmpty == false
	}

	func showReply(
		toMessageIdentifier messageIdentifier: String,
		nickname: String?,
		excerpt: String?
	) {
		replyMessageIdentifier = messageIdentifier
		replyNickname = nickname
		replyExcerpt = excerpt
	}

	func hideReply() {
		replyMessageIdentifier = nil
		replyNickname = nil
		replyExcerpt = nil
	}

	func setTypingNicknames(_ nicknames: [String]) {
		typingNicknames = nicknames
	}
}

/** Whether the message field holds the keyboard.

 The field is an AppKit view, so SwiftUI's `@FocusState` never sees it; the
 field reports its own first-responder transitions here and the capsule drawn
 around it observes them.

 First-responder status alone is not the answer. A window keeps its first
 responder while it is inactive, and `resignFirstResponder` is not sent when
 the window stops being key -- so a ring driven by that transition alone stayed
 lit on every background window in the space. Key-window status is the second
 half of the question, and both have to hold. */
@MainActor
@Observable
final class MainWindowInputFocusModel {
	/// Whether the field is its window's first responder.
	var isFirstResponder = false
	/// Whether that window is the one the keyboard is going to.
	var windowIsKey = false

	/// What the capsule draws its ring from.
	var isFocused: Bool {
		isFirstResponder && windowIsKey
	}
}

struct MainWindowInputAccessoryView: View {
	@Bindable var model: MainWindowInputAccessoryModel
	let cancelReply: () -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.tight) {
			if model.replyMessageIdentifier != nil {
				replyBanner
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}

			if model.typingNicknames.isEmpty == false {
				typingRow
					.transition(.opacity)
			}
		}
		.animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.hasContent)
	}

	private var replyBanner: some View {
		HStack(spacing: UISpacing.tight) {
			Image(systemName: "arrowshape.turn.up.left")
				.font(.caption.weight(.medium))
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)

			replyLabel

			Spacer(minLength: UISpacing.tight)

			Button(MainWindowStrings.Reply.cancel, systemImage: "xmark.circle.fill") {
				model.hideReply()
				cancelReply()
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)
			.help(MainWindowStrings.Reply.cancel)
		}
		.padding(.horizontal, UISpacing.wide)
		.frame(height: MainWindowInputBarLayout.replyBannerHeight)
		.glassEffect(.regular, in: .rect(cornerRadius: 8))
	}

	/** The banner's own text, with the message it is quoting as its tooltip.

	 Only where there is one to show: `help("")` installs an empty tooltip,
	 which AppKit draws as an empty yellow box over the banner. */
	@ViewBuilder
	private var replyLabel: some View {
		let label = Text(replyText)
			.font(.caption)
			.lineLimit(1)
			.truncationMode(.tail)

		if let excerpt = model.replyExcerpt, excerpt.isEmpty == false {
			label.help(excerpt)
		} else {
			label
		}
	}

	private var replyText: AttributedString {
		var result = AttributedString(MainWindowStrings.Reply.target(model.replyNickname))
		result.font = .caption.bold()

		if let excerpt = model.replyExcerpt, excerpt.isEmpty == false {
			var suffix = AttributedString(": \(excerpt.replacingOccurrences(of: "\n", with: " "))")
			suffix.font = .caption
			suffix.foregroundColor = .secondary
			result.append(suffix)
		}

		return result
	}

	private var typingRow: some View {
		HStack(spacing: UISpacing.tight) {
			/* The dots pulse forever, which is exactly what Reduce Motion asks
			 an interface not to do; the row itself still says who is typing. */
			Image(systemName: "ellipsis")
				.font(.footnote.bold())
				.symbolEffect(
					.variableColor.cumulative.reversing,
					options: reduceMotion ? .nonRepeating : .repeating
				)
				.accessibilityHidden(true)
			Text(MainWindowStrings.Typing.caption(for: model.typingNicknames))
				.font(.caption)
				.lineLimit(1)
				.truncationMode(.tail)
		}
		.foregroundStyle(.secondary)
		.padding(.horizontal, UISpacing.wide)
		.frame(height: MainWindowInputBarLayout.typingRowHeight)
		.help(model.typingNicknames.joined(separator: ", "))
	}
}
