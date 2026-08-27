/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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

@MainActor
public extension MenuActionCoordinator {
	@objc(performSupportAction:sender:)
	func performSupportAction(_ action: TXMenuSupportAction, sender _: Any?) {
		switch action {
		case .openLogLocation: openLog(at: PathInfo.transcriptFolderURL)
		case .openChannelLogs: openLog(at: selectedChannel?.logFilePath)
		case .openAcknowledgements: openAcknowledgements()
		case .contactSupport:
			OpenLink.open(string: "https://github.com/vakesz/Glasstual/issues", inBackground: false)
		case .connectToHelpChannel: connectToSupportChannel("#glasstual")
		case .connectToTestingChannel: connectToSupportChannel("#glasstual-testing")
		@unknown default: break
		}
	}

	private func openLog(at url: URL?) {
		guard let url else { return }
		if FileManager.default.fileExists(atPath: url.path) {
			NSWorkspace.shared.open(url)
			return
		}
		_ = TDCAlert.alert(
			withMessage: PromptStrings.Logging.emptyAlertBody,
			title: PromptStrings.Logging.noLogsTitle,
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil
		)
	}

	private func openAcknowledgements() {
		guard let url = Bundle.main.url(
			forResource: "Acknowledgements",
			withExtension: "pdf",
			subdirectory: "Documentation"
		) else {
			NSLog("Acknowledgements.pdf is missing from the application bundle")
			return
		}
		NSWorkspace.shared.open(url)
	}

	private func connectToSupportChannel(_ channel: String) {
		Extras.createConnectionToServer(
			"irc.libera.chat +6697",
			channelList: channel,
			connectWhenCreated: true,
			mergeConnectionIfPossible: true,
			selectFirstChannelAdded: true
		)
	}
}
