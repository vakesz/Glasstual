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
	/// The profile popover a click on a nickname opened, while it is open.
	private var memberInformationPopover: NSPopover?

	private lazy var nativeView = NativeTranscriptView(owner: self)
	let policy = LogPolicy()

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
		/* No theme observers here. The main window owns the fan-out: it answers
		 the theme notifications once and calls `reloadTheme()` on every
		 controller, and a transcript that also listened re-rendered twice. */
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

	/** Sends what the reader typed to the input field, and nothing else.

	 Focusing the transcript is how someone reads back through it, so the keys
	 that move a document have to reach the text view: redirecting every
	 unmodified key sent Page Up and the arrows to the input field, which took
	 the focus back and left the transcript unable to scroll at all. */
	public func keyDown(_ event: NSEvent, in _: NSView) -> Bool {
		let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		guard modifiers.isDisjoint(with: [.command, .option, .control]),
		      Self.isTextInput(event.charactersIgnoringModifiers)
		else { return false }
		viewController?.logViewKeyDown(event)
		return true
	}

	/** Whether a key stroke is text meant for the input field rather than a
	 command to the transcript.

	 AppKit spells the arrows, the paging keys, Home, End and the function keys
	 as code points in the Unicode private use area, and the space bar is the
	 page-down every document view has; all of them stay with the text view. */
	nonisolated static func isTextInput(_ characters: String?) -> Bool { // nonisolated: pure
		guard let scalar = characters?.unicodeScalars.first else { return false }
		guard scalar.value >= 0x20, scalar.value != 0x7F, scalar != " " else { return false }
		return (0xF700 ... 0xF8FF).contains(scalar.value) == false
	}

	public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		guard let fileURL = NSURL(from: sender.draggingPasteboard) as URL?, fileURL.isFileURL else {
			return false
		}
		viewController?.logViewReceivedDrop(withFile: fileURL.path)
		return true
	}

	/// Runs one of the Edit ▸ Find commands on the transcript's own find bar.
	public func performFindAction(_ action: NSTextFinder.Action) {
		nativeView.performFindAction(action)
	}

	func prepareContextTarget(at point: NSPoint) {
		contextMenuTarget = nativeView.contextTarget(at: point)
	}

	/** Shows the profile of a nickname the reader clicked in the transcript,
	 anchored to the text that named them. Only someone in the conversation has
	 a profile to show: a name that has since left is left alone. */
	func showMemberInformation(for nickname: String, relativeTo rect: NSRect, of view: NSView) {
		closeMemberInformation()
		guard let member = viewController?.associatedChannel?.findMember(nickname) else { return }
		let content = MemberListUserInfoContent(
			member: member,
			privileges: MemberListPresentation.privilegesDescription(for: member)
		)
		let popover = NSPopover()
		popover.behavior = .transient
		popover.delegate = self
		popover.contentViewController = NSHostingController(rootView: MemberListUserInfoView(content: content))
		memberInformationPopover = popover
		/* The text view is flipped, so `.maxY` is the edge below the name. */
		popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
	}

	func closeMemberInformation() {
		memberInformationPopover?.close()
		memberInformationPopover = nil
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

	/** Runs one batch of transcript edits.

	 Every mutation goes through here, which is also why the profile popover is
	 dismissed here: appending, trimming, restyling, a reaction, a decoded image
	 or the unread marker can all move or remove the text the popover is
	 anchored to, and an anchor that moves leaves the popover pointing at
	 someone else's message. */
	func performEditingBatch<Output>(_ edits: () -> Output) -> Output {
		closeMemberInformation()
		nativeView.beginEditing()
		defer { nativeView.endEditing() }
		return edits()
	}

	func clearLines() {
		performEditingBatch { nativeView.clear() }
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
		performEditingBatch { nativeView.applyTheme() }
	}
}

extension LogView: NSPopoverDelegate {
	public func popoverDidClose(_ notification: Notification) {
		if notification.object as? NSPopover === memberInformationPopover {
			memberInformationPopover = nil
		}
	}
}
