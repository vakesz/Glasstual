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

import Foundation

/** Every origin the log view is allowed to reach.

 The log view renders theme HTML — which a third-party style can replace
 wholesale — and inline-media modules inject remote resources into it. The
 Swift side, the theme scheme handler and the `Content-Security-Policy` in
 `baseLayout.mustache` all have to agree on one list of permitted origins, so
 the list is stated once, here. */
public enum LogViewContentPolicy {
	/** Theme resources are served under a private scheme rather than `file:`,
	 so the document has a single origin and no file-system read access. */
	public static let themeScheme = "glasstual-theme"

	/** The authority is fixed. A theme URL's *path* is the file-system path of
	 the resource, which keeps working the absolute paths that templates and
	 styles write into `src` and `href` attributes. */
	public static let themeHost = "theme"

	public static let themeOrigin = "\(themeScheme)://\(themeHost)"

	/** Remote origins a bundled inline-content module may load a script from.
	 Nothing else may contribute JavaScript to the log view. */
	public static let permittedScriptOrigins: Set<String> = [
		"https://platform.twitter.com",
	]

	/** Kept in sync with the `<meta http-equiv="Content-Security-Policy">` in
	 `baseLayout.mustache` by `LogViewContentPolicyTests`. The scheme handler
	 also sends it as a header, which covers styles that replace that template.

	 `'unsafe-inline'` is unavoidable: the bundled templates carry inline
	 `onload`/`onclick` handlers and an inline `<style>` element. The value of
	 this policy is the origin allowlist, not inline suppression. */
	public static let contentSecurityPolicy: String = {
		let scriptSources = ["'unsafe-inline'", "\(themeScheme):"] + permittedScriptOrigins.sorted()
		return [
			"default-src 'none'",
			"script-src \(scriptSources.joined(separator: " "))",
			"style-src 'unsafe-inline' \(themeScheme):",
			/* Inline media resolves `http` as well as `https` addresses. */
			"img-src \(themeScheme): https: http: data: blob:",
			"media-src \(themeScheme): https: http: data: blob:",
			"font-src \(themeScheme): data:",
			"connect-src \(themeScheme): https:",
			/* Video modules embed their player in a subframe. */
			"frame-src https:",
			"base-uri 'none'",
			"form-action 'none'",
		].joined(separator: "; ")
	}()

	/** The origin of `url` in `scheme://host[:port]` form, or `nil` when the
	 address carries no authority to compare. */
	public static func origin(of url: URL) -> String? {
		guard
			let scheme = url.scheme?.lowercased(),
			let host = url.host(percentEncoded: false)?.lowercased(),
			host.isEmpty == false
		else {
			return nil
		}
		/* An explicitly written default port names the same origin. */
		guard let port = url.port, port != Self.defaultPort(forScheme: scheme) else {
			return "\(scheme)://\(host)"
		}
		return "\(scheme)://\(host):\(port)"
	}

	private static func defaultPort(forScheme scheme: String) -> Int? {
		switch scheme {
		case "https": 443
		case "http": 80
		default: nil
		}
	}

	/** Whether a script resource named by an inline-content module may be
	 injected into the log view. */
	public static func permitsScriptResource(at url: URL) -> Bool {
		if url.scheme?.lowercased() == themeScheme {
			return true
		}
		guard let origin = origin(of: url) else {
			return false
		}
		return permittedScriptOrigins.contains(origin)
	}

	/** Whether the log view may navigate to `url`. The main frame never leaves
	 the theme; subframes carry the video players inline media embeds. */
	public static func permitsNavigation(to url: URL?, inMainFrame: Bool) -> Bool {
		guard let url, let scheme = url.scheme?.lowercased() else {
			return false
		}
		if scheme == themeScheme {
			return true
		}
		if scheme == "about" {
			return url.absoluteString == "about:blank"
		}
		return inMainFrame == false && scheme == "https"
	}

	/** The theme URL that serves the file at `path`. */
	public static func resourceURL(forFilePath path: String) -> URL? {
		guard path.hasPrefix("/") else {
			return nil
		}
		var components = URLComponents()
		components.scheme = themeScheme
		components.host = themeHost
		components.path = path
		return components.url
	}

	/** The file-system path a theme URL names, or `nil` when the URL is not one
	 of ours. */
	public static func filePath(for url: URL) -> String? {
		guard url.scheme?.lowercased() == themeScheme else {
			return nil
		}
		let path = url.path(percentEncoded: false)
		guard path.hasPrefix("/") else {
			return nil
		}
		return path
	}

	/** `</style` closes the element wherever it appears, so a user style sheet
	 containing it escapes into HTML. It is never valid CSS, so it is replaced
	 by a comment rather than rejected. */
	/// A CSS string literal for a user-supplied value such as a font family name.
	///
	/// The value is rendered unescaped into the theme's `<style>` block, so a name
	/// containing `"` or `</style>` would otherwise break out of the literal.
	public static func cssStringLiteral(_ value: String) -> String {
		var escaped = ""
		escaped.reserveCapacity(value.utf8.count + 2)
		for scalar in value.unicodeScalars {
			switch scalar {
			case "\\", "\"":
				escaped.append("\\")
				escaped.unicodeScalars.append(scalar)
			case "<", ">":
				/* Neither is meaningful in a font name; dropping them keeps
				 `</style>` out of the block without an escape sequence. */
				continue
			default:
				if scalar.properties.generalCategory == .control {
					continue
				}
				escaped.unicodeScalars.append(scalar)
			}
		}
		return "\"\(escaped)\""
	}

	public nonisolated static func sanitizedStyleSheetText(_ text: String?) -> String? {
		guard let text else {
			return nil
		}
		return text.replacingOccurrences(
			of: "</style",
			with: "/* removed */",
			options: [.caseInsensitive]
		)
	}
}
