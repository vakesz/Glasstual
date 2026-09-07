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
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Foundation
import SwiftUI

/** The transcript one channel or server view owns.

 It is the feature-facing handle on the AppKit adapter in
 `NativeTranscriptView.swift`: the controller and the main window speak to this
 type, and nothing outside this feature holds the view itself. */
@MainActor
public final class LogView: NSObject {
	public weak var viewController: LogController?
	let inlineImageLoader: NativeInlineImageLoader
	let viewIdentifier: String
	public var contextMenuTarget = LogPolicyTarget()
	public var selection: String?

	private lazy var nativeView = NativeTranscriptView(owner: self)
	let policy = LogPolicy()
	private let notifications = NotificationSubscriptions()

	@available(*, unavailable, message: "Use init(viewController:)")
	override public init() {
		fatalError("Use init(viewController:)")
	}

	public init(viewController: LogController) {
		self.viewController = viewController
		inlineImageLoader = viewController.inlineImageLoader
		viewIdentifier = viewController.uniqueIdentifier
		super.init()
		_ = nativeView
		for name in [Notification.Name.themeWasModified, .themeAppearanceChanged] {
			notifications.observe(name) { [weak self] _ in self?.nativeView.applyTheme() }
		}
	}

	public var hasSelection: Bool {
		selection?.isEmpty == false
	}

	public var view: NSView {
		nativeView
	}

	public func clearSelection() {
		nativeView.clearSelection()
	}

	public func takeContextMenuTarget() -> LogPolicyTarget {
		defer { contextMenuTarget = LogPolicyTarget() }
		return contextMenuTarget
	}

	public func copySelection() {
		nativeView.copySelection()
	}

	public func printContent() {
		guard let window = nativeView.window else { return }
		let operation = NSPrintOperation(view: nativeView.printableView, printInfo: .shared)
		operation.showsPrintPanel = true
		operation.showsProgressPanel = true
		operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
	}

	public func keyDown(_ event: NSEvent, in _: NSView) -> Bool {
		let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		guard modifiers.isDisjoint(with: [.command, .option, .control]) else { return false }
		viewController?.logViewKeyDown(event)
		return true
	}

	public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		guard let fileURL = NSURL(from: sender.draggingPasteboard) as URL?, fileURL.isFileURL else {
			return false
		}
		viewController?.logViewReceivedDrop(withFile: fileURL.path)
		return true
	}

	public func findString(_ searchString: String, movingForward: Bool) {
		nativeView.find(searchString, movingForward: movingForward)
	}

	func prepareContextTarget(at point: NSPoint) {
		contextMenuTarget = nativeView.contextTarget(at: point)
	}

	func contextMenu(defaultItems: [NSMenuItem]) -> NSMenu {
		policy.contextMenu(for: self, defaultMenuItems: defaultItems)
	}

	func setTopic(_ topic: String?) {
		nativeView.setTopic(topic)
	}

	func setBottomContentInset(_ inset: CGFloat) {
		nativeView.setBottomContentInset(inset)
	}

	func setBufferLimit(_ limit: Int) {
		performEditingBatch { nativeView.setBufferLimit(limit) }
	}

	func setTextScale(_ scale: CGFloat) {
		performEditingBatch { nativeView.setTextScale(scale) }
	}

	func replaceLines(_ lines: [TranscriptLine]) {
		performEditingBatch { nativeView.replace(with: lines) }
	}

	func appendLines(_ lines: [TranscriptLine]) {
		performEditingBatch { nativeView.append(lines) }
	}

	@discardableResult
	func prependLines(_ lines: [TranscriptLine]) -> [String] {
		performEditingBatch { nativeView.prepend(lines) }
	}

	var displayedLines: [TranscriptLine] {
		nativeView.lines
	}

	var displayedBounds: TranscriptDisplayedBounds {
		TranscriptDisplayedBounds(
			oldest: nativeView.lines.first?.lineNumber, newest: nativeView.lines.last?.lineNumber,
			count: nativeView.lines.count,
			remainingCapacity: max(0, LogViewBufferPolicy.validLimits.upperBound - nativeView.lines.count)
		)
	}

	func performEditingBatch<Output>(_ edits: () -> Output) -> Output {
		nativeView.beginEditing()
		defer { nativeView.endEditing() }
		return edits()
	}

	func clearLines() {
		nativeView.clear()
	}

	func updateDelivery(_ update: TranscriptDeliveryUpdate) {
		performEditingBatch { nativeView.updateDelivery(update) }
	}

	func updateReactions(_ reactions: [String: [String]], messageIdentifier: String) {
		performEditingBatch { nativeView.updateReactions(reactions, messageIdentifier: messageIdentifier) }
	}

	func setUnreadMarker(_ mark: TranscriptScrollbackMark) {
		performEditingBatch { nativeView.setUnreadMarker(mark) }
	}

	func jump(to lineNumber: String) -> Bool {
		nativeView.jump(to: lineNumber)
	}

	func scrollToBottom() {
		nativeView.scrollToBottom()
	}

	@discardableResult
	func addInlineImage(_ image: TranscriptInlineImage) -> Bool {
		performEditingBatch { nativeView.addInlineImage(image) }
	}

	func applyTheme() {
		nativeView.applyTheme()
	}
}
