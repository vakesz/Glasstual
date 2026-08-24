/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TVCDockIcon)
public final class DockIcon: NSObject {
	private nonisolated(unsafe) static var cachedHighlightCount: Int = -1
	private nonisolated(unsafe) static var cachedMessageCount: Int = -1

	@objc public class func updateDockIcon() {
		guard TPCPreferences.displayDockBadge() else {
			return
		}

		var highlightCount: UInt = 0
		var messageCount: UInt = 0

		for client in NSObject.masterController().world.clientList as? [IRCClient] ?? [] {
			for channel in client.channelList as? [IRCChannel] ?? [] {
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

	@objc public class func resetCachedCount() {
		cachedMessageCount = -1
		cachedHighlightCount = -1
	}

	@objc public class func drawWithoutCount() {
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

	@objc(drawWithHighlightCount:messageCount:)
	public class func draw(withHighlightCount highlightCount: UInt, messageCount: UInt) {
		if cachedHighlightCount == Int(highlightCount), cachedMessageCount == Int(messageCount) {
			return
		}

		cachedHighlightCount = Int(highlightCount)
		cachedMessageCount = Int(messageCount)

		let dockTile = NSApp.dockTile

		if highlightCount == 0 {
			dockTile.contentView = nil
			dockTile.badgeLabel = badgeString(forCount: messageCount)
			dockTile.display()
			return
		}

		dockTile.badgeLabel = badgeString(forCount: messageCount + highlightCount)

		var badgeView = dockTile.contentView as? DockIconBadgeView

		if badgeView == nil {
			badgeView = DockIconBadgeView(
				frame: NSRect(x: 0, y: 0, width: dockTile.size.width, height: dockTile.size.height)
			)
			dockTile.contentView = badgeView
		}

		badgeView?.highlightCount = highlightCount
		badgeView?.messageCount = messageCount
		badgeView?.needsDisplay = true
		dockTile.display()
	}

	@objc(badgeStringForCount:)
	public class func badgeString(forCount count: UInt) -> String {
		if count > 9999 {
			return LocalizedKey("TVCMainWindow[dki-bg]", formattedNumber(9999))
		}

		return formattedNumber(Int(count)) as String
	}
}

@objc(TVCDockIconBadgeView)
public final class DockIconBadgeView: NSView {
	@objc public var highlightCount: UInt = 0
	@objc public var messageCount: UInt = 0

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

		if highlightCount > 0 {
			let top = NSMaxY(bounds) - badgeHeight - separator

			_ = drawBadge(
				withCount: highlightCount,
				color: .systemGreen,
				topRight: NSPoint(x: NSMaxX(bounds), y: top),
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
			x: NSMidX(frame) - (textSize.width / 2.0),
			y: NSMidY(frame) - (textSize.height / 2.0)
		)

		string.draw(at: textOrigin, withAttributes: attributes)

		return frame
	}
}
