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

import SwiftUI

/// The highlight condition is a value type, so this protocol is dispatched in
/// Swift rather than through the delegate's Objective-C selector table.
@MainActor
public protocol HighlightEntrySheetDelegate: AnyObject {
	func highlightEntrySheet(_ sender: HighlightEntrySheet, didSave configuration: HighlightMatchCondition)
	func highlightEntrySheetDidClose(_ sender: HighlightEntrySheet)
}

@MainActor
public final class HighlightEntrySheet: MainWindowSheetSession {
	let model: HighlightEntryModel

	private let content: HighlightEntryContent

	public init(config: HighlightMatchCondition?, channels: [ChannelConfig]) {
		content = .current
		model = HighlightEntryModel(
			configuration: config,
			channels: channels.map {
				HighlightEntryChannel(id: $0.uniqueIdentifier, name: $0.channelName)
			}
		)

		super.init(window: nil)
		installSheet()
	}

	private func installSheet() {
		let rootView = HighlightEntryView(
			model: model,
			content: content,
			behaviorDidChange: { [weak self] behavior in
				self?.model.setBehavior(behavior)
			},
			keywordDidChange: { [weak self] keyword in
				self?.model.updateKeyword(keyword)
			},
			channelSelectionDidChange: { [weak self] selection in
				self?.model.setChannelSelection(selection)
			},
			submit: { [weak self] in
				self?.ok(nil)
			},
			cancel: { [weak self] in
				self?.cancel(nil)
			}
		)
		setContent(rootView)
	}

	public func start() {
		startSheet()
	}

	override public func ok(_ sender: Any?) {
		guard model.validateForSubmission() else {
			return
		}

		(delegate as? any HighlightEntrySheetDelegate)?.highlightEntrySheet(
			self,
			didSave: model.configurationForSubmission()
		)

		super.ok(sender)
	}

	override public func sheetDidEnd(withReturnCode _: Int) {
		(delegate as? any HighlightEntrySheetDelegate)?.highlightEntrySheetDidClose(self)
	}
}
