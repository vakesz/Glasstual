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

struct MainWindowInputAccessoryView: View {
	@Bindable var model: MainWindowInputAccessoryModel
	let cancelReply: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			if model.replyMessageIdentifier != nil {
				replyBanner
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}

			if model.typingNicknames.isEmpty == false {
				typingRow
					.transition(.opacity)
			}
		}
		.animation(.easeOut(duration: 0.18), value: model.hasContent)
	}

	private var replyBanner: some View {
		HStack(spacing: 6) {
			Image(systemName: "arrowshape.turn.up.left")
				.font(.system(size: 12, weight: .medium))
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)

			Text(replyText)
				.font(.caption)
				.lineLimit(1)
				.truncationMode(.tail)
				.help(model.replyExcerpt ?? "")

			Spacer(minLength: 4)

			Button(MainWindowStrings.Reply.cancel, systemImage: "xmark.circle.fill") {
				model.hideReply()
				cancelReply()
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 10)
		.frame(height: 30)
		.background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
		HStack(spacing: 5) {
			Image(systemName: "ellipsis")
				.font(.system(size: 13, weight: .bold))
				.symbolEffect(.variableColor.cumulative.reversing, options: .repeating)
				.accessibilityHidden(true)
			Text(MainWindowStrings.Typing.caption(for: model.typingNicknames))
				.font(.caption)
				.lineLimit(1)
				.truncationMode(.tail)
		}
		.foregroundStyle(.secondary)
		.padding(.horizontal, 10)
		.frame(height: 18)
		.help(model.typingNicknames.joined(separator: ", "))
	}
}
