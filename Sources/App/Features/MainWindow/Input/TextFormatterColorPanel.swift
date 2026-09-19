// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** The shared colour panel, while the formatting menu has it.

 The panel is shared with every other user of it in the application: while it is
 open on our behalf it sends its action here, and once it closes the target and
 action are cleared so a later, unrelated presentation does not keep formatting
 the message field. One action and one closure rather than a selector per
 destination -- which colour the panel is picking is the caller's business, not
 the panel's. */
@MainActor
final class TextFormatterColorPanel: NSObject {
	/// Where the chosen colour goes, while a presentation of ours is up.
	private var colorChanged: ((NSColor) -> Void)?
	/// Which presentation is current. The close notification arrives a turn
	/// late, so a teardown has to be able to tell whether the panel it is
	/// tearing down is still the one it presented.
	private var presentation = 0
	private var hasAttachedColorList = false
	/// The panel's close notification, held while the panel is up.
	private let notifications = NotificationSubscriptions()

	/// Opens the panel on `initialColor` and reports every colour the reader
	/// picks until it closes.
	func present(startingAt initialColor: NSColor, colorChanged: @escaping (NSColor) -> Void) {
		attachColorList()
		self.colorChanged = colorChanged

		let colorPanel = NSColorPanel.shared

		colorPanel.setTarget(self)
		colorPanel.setAction(#selector(panelColorChanged(_:)))
		colorPanel.showsAlpha = false
		colorPanel.mode = .colorList
		colorPanel.color = initialColor

		presentation += 1
		let presentation = presentation

		notifications.cancelAll()
		notifications.observe(NSWindow.willCloseNotification, object: colorPanel) { [weak self] notification in
			self?.willClose(notification, from: presentation)
		}

		colorPanel.orderFront(nil)
	}

	/** Puts the IRC palette in the colour panel's list picker, once.

	 Attached from the presentation rather than when the window installs the
	 menu. `NSColorPanel.shared` builds the entire system picker the first time
	 anything asks for it — the colour wheel included, which draws through
	 CoreImage and so loads Metal and its shader caches — and a session that
	 never opens a colour picker has no use for any of that.

	 The list is built here rather than loaded from a file: the colours are
	 already an array in the binary. */
	private func attachColorList() {
		guard hasAttachedColorList == false else {
			return
		}

		hasAttachedColorList = true

		let colorList = NSColorList(name: ApplicationStrings.ircColors)

		for (index, color) in NSColor.formatterColors.enumerated() {
			colorList.setColor(color, forKey: ApplicationStrings.ircColor(at: index))
		}

		NSColorPanel.shared.attachColorList(colorList)
	}

	@objc private func panelColorChanged(_ sender: NSColorPanel) {
		colorChanged?(sender.color)
	}

	/** The notification lands a turn after the panel closed, by which time this
	 menu may have presented the shared panel again. Clearing the target off
	 that new presentation would leave the picker up and every colour it reports
	 going nowhere, so a teardown only runs for the presentation it belongs to. */
	private func willClose(_ notification: Notification, from presentation: Int) {
		guard let colorPanel = notification.object as? NSColorPanel,
		      presentation == self.presentation
		else {
			return
		}

		notifications.cancelAll()
		colorChanged = nil

		/* NSColorPanel has no target getter, so this cannot check whether
		 another caller took the panel over in the meantime. */
		colorPanel.setTarget(nil)
		colorPanel.setAction(nil)
	}
}
