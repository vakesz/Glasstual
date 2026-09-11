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
public final class MainWindowInputAccessoryModel {
	public private(set) var replyMessageIdentifier: String?
	public private(set) var replyNickname: String?
	public private(set) var replyExcerpt: String?
	public private(set) var typingNicknames: [String] = []

	public var hasContent: Bool {
		replyMessageIdentifier != nil || typingNicknames.isEmpty == false
	}

	public func showReply(
		toMessageIdentifier messageIdentifier: String,
		nickname: String?,
		excerpt: String?
	) {
		replyMessageIdentifier = messageIdentifier
		replyNickname = nickname
		replyExcerpt = excerpt
	}

	public func hideReply() {
		replyMessageIdentifier = nil
		replyNickname = nil
		replyExcerpt = nil
	}

	public func setTypingNicknames(_ nicknames: [String]) {
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
public final class MainWindowInputFocusModel {
	/// Whether the field is its window's first responder.
	public internal(set) var isFirstResponder = false
	/// Whether that window is the one the keyboard is going to.
	public internal(set) var windowIsKey = false

	/// What the capsule draws its ring from.
	public var isFocused: Bool {
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
				.font(.system(size: 12, weight: .medium))
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)

			Text(replyText)
				.font(.caption)
				.lineLimit(1)
				.truncationMode(.tail)
				.help(model.replyExcerpt ?? "")

			Spacer(minLength: UISpacing.tight)

			Button(MainWindowStrings.Reply.cancel, systemImage: "xmark.circle.fill") {
				model.hideReply()
				cancelReply()
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)
		}
		.padding(.horizontal, UISpacing.wide)
		.frame(height: MainWindowInputBarLayout.replyBannerHeight)
		.glassEffect(.regular, in: .rect(cornerRadius: 8))
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
				.font(.system(size: 13, weight: .bold))
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
