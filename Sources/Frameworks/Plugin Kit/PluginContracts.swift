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

public enum PluginCompatibility {
	/// First host contract that loads Swift-native plugins without Glasstual.h.
	public static let minimumHostVersion = "8.0.0"
}

/// Marker protocol for every Swift plugin loaded by Glasstual.
///
/// Every callback in this file is main-actor isolated: plugins are loaded into
/// the application process and talk to live UI and IRC models, so the host has
/// no other place to call them from.
@MainActor
public protocol GlasstualPlugin: AnyObject {
	func pluginLoaded(using host: PluginHostContext)

	func pluginWillUnload()
}

public extension GlasstualPlugin {
	func pluginLoaded(using _: PluginHostContext) {}

	func pluginWillUnload() {}
}

@MainActor
public protocol PluginPreferencesProviding: AnyObject {
	/// `nil` when the plugin does not currently supply a preference pane.
	var pluginPreferencesPane: PluginPreferencesPane? { get }
}

/// A plugin-owned SwiftUI preferences surface.
///
/// The closure preserves the plugin's ownership of its state while allowing the
/// host to create the view in the Settings scene. It is main-actor isolated with
/// the rest of the in-process plugin UI contract.
@MainActor
public struct PluginPreferencesPane {
	public let title: String
	private let content: () -> AnyView

	public init(title: String, @ViewBuilder content: @escaping () -> some View) {
		self.title = title
		self.content = { AnyView(content()) }
	}

	public func makeView() -> AnyView {
		content()
	}
}

@MainActor
public protocol PluginTextEventHandling: AnyObject {
	func receivedText(_ event: PluginTextEvent) -> Bool
}

@MainActor
public protocol PluginCommandHandling: AnyObject {
	var subscribedUserInputCommands: [String] { get }
	func userInputCommandInvoked(_ invocation: PluginCommandInvocation)
}

@MainActor
public protocol PluginIncomingCommandHandling: AnyObject {
	func receivedCommand(_ event: PluginIncomingCommandEvent) -> Bool
}

@MainActor
public protocol PluginServerInputHandling: AnyObject {
	var subscribedServerInputCommands: [String] { get }
	func didReceiveServerInput(_ input: PluginServerInput, client: PluginClient)
}

@MainActor
public protocol PluginServerMessageIntercepting: AnyObject {
	func interceptServerInput(_ message: PluginServerMessage, client: PluginClient) -> PluginServerMessage?
}

/// The one callback the host cannot make on the main actor: message bodies are
/// rendered on a background queue by a synchronous renderer. Its event is a
/// `Sendable` value and its result is a `String`, so an implementation only has
/// to keep its own state safe.
public protocol PluginMessageRendering: AnyObject, Sendable {
	nonisolated func willRenderMessage(_ event: PluginRenderEvent) -> String? // nonisolated: pure
}

@MainActor
public protocol PluginUserInputIntercepting: AnyObject {
	func interceptUserInput(_ input: PluginUserInput) -> Any?
}

@MainActor
public protocol PluginPostedMessageHandling: AnyObject {
	func didPostNewMessage(_ message: PluginPostedMessage)
}

@MainActor
public protocol PluginOutputSuppressionProviding: AnyObject {
	var pluginOutputSuppressionRules: [PluginOutputSuppressionRule] { get }
}
