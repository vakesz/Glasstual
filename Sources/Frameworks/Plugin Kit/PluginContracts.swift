/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
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

public enum PluginCompatibility {
	/// First host contract that loads Swift-native plugins without Glasstual.h.
	public static let minimumHostVersion = "8.0.0"
}

/// Marker protocol for every Swift plugin loaded by Glasstual.
public protocol GlasstualPlugin: AnyObject {
	@MainActor
	func pluginLoaded(using host: PluginHostContext)

	@MainActor
	func pluginWillUnload()
}

public extension GlasstualPlugin {
	@MainActor
	func pluginLoaded(using _: PluginHostContext) {}

	@MainActor
	func pluginWillUnload() {}
}

public protocol PluginPreferencesProviding: AnyObject {
	@MainActor
	var pluginPreferencesPaneMenuItemName: String { get }

	@MainActor
	var pluginPreferencesPaneView: NSView { get }
}

public protocol PluginTextEventHandling: AnyObject {
	@MainActor
	func receivedText(_ event: PluginTextEvent) -> Bool
}

public protocol PluginCommandHandling: AnyObject {
	var subscribedUserInputCommands: [String] { get }
	func userInputCommandInvoked(_ invocation: PluginCommandInvocation)
}

public protocol PluginIncomingCommandHandling: AnyObject {
	@MainActor
	func receivedCommand(_ event: PluginIncomingCommandEvent) -> Bool
}

public protocol PluginServerInputHandling: AnyObject {
	var subscribedServerInputCommands: [String] { get }
	func didReceiveServerInput(_ input: PluginServerInput, client: PluginClient)
}

public protocol PluginServerMessageIntercepting: AnyObject {
	@MainActor
	func interceptServerInput(_ message: PluginServerMessage, client: PluginClient) -> PluginServerMessage?
}

public protocol PluginMessageRendering: AnyObject {
	func willRenderMessage(_ event: PluginRenderEvent) -> String?
}

public protocol PluginUserInputIntercepting: AnyObject {
	@MainActor
	func interceptUserInput(_ input: PluginUserInput) -> Any?
}

public protocol PluginPostedMessageHandling: AnyObject {
	func didPostNewMessage(_ message: PluginPostedMessage)
}

public protocol PluginJavaScriptPayloadHandling: AnyObject {
	func didReceiveJavaScriptPayload(_ payload: PluginJavaScriptPayload)
}

public protocol PluginOutputSuppressionProviding: AnyObject {
	var pluginOutputSuppressionRules: [PluginOutputSuppressionRule] { get }
}
