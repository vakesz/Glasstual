/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import SwiftUI

/// The grouped `Form` every pane is laid out in, so the metrics live once.
struct PreferencesPaneLayout<Content: View>: View {
	@ViewBuilder let content: Content

	var body: some View {
		Form {
			content
		}
		.formStyle(.grouped)
		.scrollContentBackground(.hidden)
	}
}

/// Explanatory text below a control, in the secondary style the nib used.
struct PreferencesNote: View {
	let text: String

	init(_ text: String) {
		self.text = text
	}

	var body: some View {
		Text(verbatim: text)
			.font(.callout)
			.foregroundStyle(.secondary)
			.fixedSize(horizontal: false, vertical: true)
			.frame(maxWidth: .infinity, alignment: .leading)
	}
}

/// A checkbox driven by a preference binding, with the label the nib carried.
struct PreferencesToggle: View {
	let title: String
	@Binding var isOn: Bool

	var body: some View {
		Toggle(isOn: $isOn) {
			Text(verbatim: title)
		}
		.toggleStyle(.checkbox)
	}
}

/** The nib's combo boxes: a field the user can type into, with the list of
 values it shipped reachable from the button beside it. */
struct PreferencesComboField: View {
	let title: String
	let presets: [String]
	@Binding var text: String

	var body: some View {
		HStack(spacing: 6) {
			TextField("", text: $text)
				.labelsHidden()
				.accessibilityLabel(Text(verbatim: title))
			Menu {
				ForEach(presets, id: \.self) { preset in
					Button(preset) {
						text = preset
					}
				}
			} label: {
				EmptyView()
			}
			.menuStyle(.borderlessButton)
			.frame(width: 16)
			.accessibilityLabel(Text(verbatim: title))
		}
	}
}

/** An AppKit view a pane still owns — a plugin's preference pane, or the alert
 table the Notifications pane hosts.

 The view is built once and handed over; SwiftUI only places it, which is why
 the height has to be stated rather than measured. */
struct PreferencesHostedView: NSViewRepresentable {
	let height: CGFloat
	let makeView: () -> NSView

	func makeNSView(context _: Context) -> NSView {
		let container = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: height))
		let hosted = makeView()
		hosted.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(hosted)
		NSLayoutConstraint.activate([
			hosted.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			hosted.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			hosted.topAnchor.constraint(equalTo: container.topAnchor),
			hosted.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])
		return container
	}

	func updateNSView(_: NSView, context _: Context) {}

	func sizeThatFits(_ proposal: ProposedViewSize, nsView _: NSView, context _: Context) -> CGSize? {
		CGSize(width: proposal.width ?? 400, height: height)
	}
}

/// The same view for the plugin panes, which supply an `NSView` directly.
extension PreferencesHostedView {
	init(view: NSView, height: CGFloat) {
		self.init(height: height, makeView: { view })
	}
}
