/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

@MainActor
struct HighlightEntryView: View {
	@Bindable var model: HighlightEntryModel
	@FocusState private var keywordFieldIsFocused: Bool

	let content: HighlightEntryContent
	let behaviorDidChange: @MainActor (HighlightMatchBehavior) -> Void
	let keywordDidChange: @MainActor (String) -> Void
	let channelSelectionDidChange: @MainActor (HighlightChannelSelection) -> Void
	let submit: @MainActor () -> Void
	let cancel: @MainActor () -> Void

	private var behavior: Binding<HighlightMatchBehavior> {
		Binding(
			get: { model.behavior },
			set: behaviorDidChange
		)
	}

	private var keyword: Binding<String> {
		Binding(
			get: { model.keyword },
			set: keywordDidChange
		)
	}

	private var channelSelection: Binding<HighlightChannelSelection> {
		Binding(
			get: { model.channelSelection },
			set: channelSelectionDidChange
		)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Picker(content.matchTypeAccessibilityLabel, selection: behavior) {
					ForEach(HighlightMatchBehavior.allCases) { behavior in
						Text(verbatim: content.title(for: behavior))
							.tag(behavior)
					}
				}
				.labelsHidden()
				.frame(width: 100)
				.accessibilityLabel(Text(verbatim: content.matchTypeAccessibilityLabel))

				Text(verbatim: content.keywordConnector)
					.fixedSize()

				TextField("", text: keyword)
					.labelsHidden()
					.focused($keywordFieldIsFocused)
					.accessibilityLabel(Text(verbatim: content.keywordAccessibilityLabel))
					.accessibilityHint(
						Text(verbatim: model.validationError ?? content.keywordAccessibilityHint)
					)
					.overlay {
						if model.validationError != nil {
							RoundedRectangle(cornerRadius: 5)
								.stroke(.red, lineWidth: 1)
								.allowsHitTesting(false)
						}
					}
					.popover(isPresented: $model.isValidationMessagePresented) {
						if let validationError = model.validationError {
							Text(verbatim: validationError)
								.padding(10)
						}
					}
					.onSubmit(submit)
			}

			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Text(verbatim: content.channelConnector)
					.fixedSize()

				Picker(content.channelAccessibilityLabel, selection: channelSelection) {
					Text(verbatim: content.allChannelsTitle)
						.tag(HighlightChannelSelection.all)

					if model.channels.isEmpty == false {
						Divider()
					}

					ForEach(model.channels) { channel in
						Text(verbatim: channel.name)
							.tag(HighlightChannelSelection.channel(id: channel.id))
					}
				}
				.labelsHidden()
				.frame(maxWidth: .infinity)
				.accessibilityLabel(Text(verbatim: content.channelAccessibilityLabel))
				.accessibilityHint(Text(verbatim: content.channelAccessibilityHint))
			}

			HStack(spacing: 8) {
				Spacer()

				Button(action: cancel) {
					Text(verbatim: content.cancelButtonTitle)
				}
				.keyboardShortcut(.cancelAction)

				Button(action: submit) {
					Text(verbatim: content.saveButtonTitle)
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 500, height: 150)
		.onAppear {
			keywordFieldIsFocused = true
		}
		.onExitCommand(perform: cancel)
	}
}
