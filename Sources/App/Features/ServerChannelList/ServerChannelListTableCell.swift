// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// Formatting the complete server topic is deferred until its tooltip is
/// requested. Layout and scrolling only see the bounded display string.
final class ServerChannelListTableCell: NSTableCellView, NSViewToolTipOwner {
	var topic = "" {
		didSet {
			guard topic != oldValue else { return }
			plainTopic = nil
			needsLayout = true
		}
	}

	private var plainTopic: String?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		let label = NSTextField(labelWithString: "")
		label.font = .systemFont(ofSize: NSFont.systemFontSize)
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)
		textField = label
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
			label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) is unavailable")
	}

	override func layout() {
		super.layout()
		removeAllToolTips()
		if topic.isEmpty == false {
			addToolTip(bounds, owner: self, userData: nil)
		}
	}

	func view(_: NSView, stringForToolTip _: NSView.ToolTipTag, point _: NSPoint, userData _: UnsafeMutableRawPointer?) -> String {
		if let plainTopic {
			return plainTopic
		}
		let plain = FormattingParser.parse(topic).string
		plainTopic = plain
		return plain
	}
}
