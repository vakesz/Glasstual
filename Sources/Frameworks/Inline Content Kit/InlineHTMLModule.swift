/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
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

import CocoaExtensions
import Foundation

/// Presents markup a remote endpoint supplied.
///
/// The markup is not the framework's own, so anything rendered through here is
/// untrusted by default; a module that wraps it says so for itself.
public enum InlineHTMLContent {
	public static let entrypoint = "_ICMInlineHTML"

	public static var styleResources: [URL] {
		[InlineContentTemplate.componentURL(named: "ICMInlineHTML", extension: "css")].compactMap(\.self)
	}

	public static var scriptResources: [URL] {
		[InlineContentTemplate.componentURL(named: "ICMInlineHTML", extension: "js")].compactMap(\.self)
	}

	private static var templateURL: URL? {
		InlineContentTemplate.componentURL(named: "ICMInlineHTML", extension: "mustache")
	}

	/// Wraps `unescapedHTML` in the framework's container.
	///
	/// `extraScriptResources` and `overrideEntrypoint` let a module add the
	/// script its embed needs — a tweet needs Twitter's widget loader — without
	/// having to restate the container's own resources.
	public static func produce(
		_ values: InlineContentPayloadValues,
		unescapedHTML: String,
		extraScriptResources: [URL] = [],
		overrideEntrypoint: String? = nil
	) -> InlineContentOutcome {
		var values = values

		values.styleResources = styleResources
		values.scriptResources = scriptResources + extraScriptResources
		values.entrypoint = overrideEntrypoint ?? entrypoint

		let attributes: [String: JavaScriptValue] = [
			"classAttribute": .string(values.classAttribute),
			"unescapedHTML": .string(unescapedHTML),
			"uniqueIdentifier": .string(values.uniqueIdentifier),
		]

		return InlineContentTemplate.outcome(templateURL, attributes, into: values)
	}
}
