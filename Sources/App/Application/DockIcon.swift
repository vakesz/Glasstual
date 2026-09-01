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

public final class DockIcon: NSObject {
	@MainActor private static var cachedHighlightCount: Int = -1
	@MainActor private static var cachedMessageCount: Int = -1

	@MainActor public static func updateDockIcon() {
		guard Preferences.Notifications.displayDockBadge.value else {
			return
		}

		guard let world = AppController.shared.world else {
			// World is not yet initialized (e.g. called during early nib wake-up).
			return
		}

		var highlightCount: UInt = 0
		var messageCount: UInt = 0

		for client in world.clientList {
			for channel in client.channelList {
				if channel.config.pushNotifications {
					messageCount += UInt(channel.dockUnreadCount)
				}

				highlightCount += UInt(channel.nicknameHighlightCount)
			}
		}

		if messageCount == 0, highlightCount == 0 {
			drawWithoutCount()
		} else {
			draw(withHighlightCount: highlightCount, messageCount: messageCount)
		}
	}

	@MainActor public static func resetCachedCount() {
		cachedMessageCount = -1
		cachedHighlightCount = -1
	}

	@MainActor public static func drawWithoutCount() {
		if cachedHighlightCount == 0, cachedMessageCount == 0 {
			return
		}

		cachedMessageCount = 0
		cachedHighlightCount = 0

		let dockTile = NSApp.dockTile
		dockTile.badgeLabel = nil
		dockTile.contentView = nil
		dockTile.display()
	}

	@MainActor public static func draw(withHighlightCount highlightCount: UInt, messageCount: UInt) {
		if cachedHighlightCount == Int(highlightCount), cachedMessageCount == Int(messageCount) {
			return
		}

		cachedHighlightCount = Int(highlightCount)
		cachedMessageCount = Int(messageCount)

		let dockTile = NSApp.dockTile

		guard highlightCount > 0 || messageCount > 0 else {
			dockTile.badgeLabel = nil
			dockTile.contentView = nil
			dockTile.display()

			return
		}

		/* One strategy draws both counts: the badge view. Falling back to the
		 system badge label whenever the highlight count was zero made the icon
		 change shape depending on whether anyone had said your name, and the
		 label has to be cleared anyway or the count is drawn twice — once in
		 the label and once in the pill sitting on top of it. */
		dockTile.badgeLabel = nil

		let badgeView = dockTile.contentView as? DockIconBadgeView ?? {
			let view = DockIconBadgeView(frame: NSRect(origin: .zero, size: dockTile.size))
			dockTile.contentView = view

			return view
		}()

		badgeView.highlightCount = highlightCount
		badgeView.messageCount = messageCount
		badgeView.needsDisplay = true
		dockTile.display()
	}

	public static func badgeString(forCount count: UInt) -> String {
		if count > 9999 {
			return MainWindowStrings.Dock.overflowBadge(maximum: formattedNumber(9999) as String)
		}

		return formattedNumber(Int(count)) as String
	}
}

public final class DockIconBadgeView: NSView {
	public var highlightCount: UInt = 0
	public var messageCount: UInt = 0

	override public var isFlipped: Bool {
		false
	}

	override public func draw(_: NSRect) {
		let bounds = bounds

		NSApp.applicationIconImage?.draw(
			in: bounds,
			from: .zero,
			operation: .sourceOver,
			fraction: 1.0
		)

		let badgeHeight = floor(bounds.size.height * 0.26)
		let separator: CGFloat = 1.0
		var top = bounds.maxY - badgeHeight - separator

		if highlightCount > 0 {
			let pill = drawBadge(
				withCount: highlightCount,
				color: .systemGreen,
				topRight: NSPoint(x: bounds.maxX, y: top),
				height: badgeHeight
			)

			top = pill.minY - separator
		}

		if messageCount > 0 {
			_ = drawBadge(
				withCount: messageCount,
				color: .systemRed,
				topRight: NSPoint(x: bounds.maxX, y: top),
				height: badgeHeight
			)
		}
	}

	@discardableResult
	private func drawBadge(
		withCount count: UInt,
		color: NSColor,
		topRight: NSPoint,
		height: CGFloat
	) -> NSRect {
		let string = DockIcon.badgeString(forCount: count)
		let attributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.boldSystemFont(ofSize: height * 0.62),
			.foregroundColor: NSColor.white,
		]

		let textSize = string.size(withAttributes: attributes)
		let width = max(height, ceil(textSize.width + (height * 0.6)))
		let frame = NSRect(x: topRight.x - width, y: topRight.y - height, width: width, height: height)

		let pill = NSBezierPath(roundedRect: frame, xRadius: height / 2.0, yRadius: height / 2.0)
		color.setFill()
		pill.fill()

		NSColor.white.withAlphaComponent(0.9).setStroke()
		pill.lineWidth = max(1.0, height * 0.06)
		pill.stroke()

		let textOrigin = NSPoint(
			x: frame.midX - (textSize.width / 2.0),
			y: frame.midY - (textSize.height / 2.0)
		)

		string.draw(at: textOrigin, withAttributes: attributes)

		return frame
	}
}
