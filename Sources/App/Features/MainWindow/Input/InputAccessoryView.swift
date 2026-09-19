// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct InputAccessoryView: View {
	@Bindable var model: InputAccessoryModel
	let cancelReply: () -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.tight) {
			if model.replyMessageIdentifier != nil {
				replyBanner
					.transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
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

			Button(String(localized: .MainWindow.cancelReply), systemImage: "xmark.circle.fill") {
				model.hideReply()
				cancelReply()
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)
			.help(String(localized: .MainWindow.cancelReply))
		}
		.padding(.horizontal, UISpacing.wide)
		.frame(height: InputBarLayout.replyBannerHeight)
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
		var result = AttributedString(InputAccessoryView.replyTarget(model.replyNickname))
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
					options: .repeating,
					isActive: reduceMotion == false
				)
				.accessibilityHidden(true)
			Text(InputAccessoryView.typingCaption(for: model.typingNicknames))
				.font(.caption)
				.lineLimit(1)
				.truncationMode(.tail)
		}
		.foregroundStyle(.secondary)
		.padding(.horizontal, UISpacing.wide)
		.frame(height: InputBarLayout.typingRowHeight)
		.help(model.typingNicknames.joined(separator: ", "))
	}
}

extension InputAccessoryView {
	/// Whom the draft replies to, or the stand-in when the reply carries no name.
	static func replyTarget(_ nickname: String?) -> String {
		let recipient = nickname.flatMap { $0.isEmpty ? nil : $0 }
			?? String(localized: .MainWindow.inputBarReplyBannerMessage)
		return String(localized: .MainWindow.inputBarReplyBannerReplying(recipient))
	}

	/// One, two, or a count: the caption names the people it can name.
	static func typingCaption(for nicknames: [String]) -> String {
		precondition(nicknames.isEmpty == false, "Typing captions require at least one nickname")

		switch nicknames.count {
		case 1:
			return String(localized: .MainWindow.isTyping(nicknames[0]))
		case 2:
			return String(localized: .MainWindow.areTyping(nicknames[0], nicknames[1]))
		default:
			return String(localized: .MainWindow.typingCount(nicknames.count))
		}
	}
}
