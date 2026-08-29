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
import Mustache
import os

/// Loading and rendering the Mustache templates modules present through.
///
/// `Template` is a reference type from GRMustache, so it is created and used
/// inside one call and never stored: a module is a value and holds none.
public enum InlineContentTemplate {
	private static let logger = Logger(
		subsystem: "com.vakesz.glasstual.InlineContentLoader",
		category: "Modules"
	)

	/// A component that ships beside the executable, under `Components`.
	public static func componentURL(named name: String, extension pathExtension: String) -> URL? {
		Bundle.main.url(forResource: name, withExtension: pathExtension, subdirectory: "Components")
	}

	/// Renders `attributes` through the template at `url`.
	///
	/// Returns nil when the template is missing or unreadable, which the
	/// caller reports as "nothing to show" rather than as a failure: a missing
	/// component is a packaging problem, not something the server did.
	public static func render(_ url: URL?, _ attributes: [String: JavaScriptValue]) throws -> String? {
		guard let url, url.isFileURL else { return nil }

		let template: Template

		do {
			template = try Template(URL: url)
		} catch {
			logger.error(
				"Failed to load template '\(url.standardizedFileURL.path, privacy: .public)': \(error.localizedDescription, privacy: .public)"
			)

			return nil
		}

		return try template.render(attributes.mapValues(\.bridgedObject))
	}

	/// Renders and folds the two failure shapes into one outcome, which is what
	/// every module wants: a missing template cancels, a render error fails.
	public static func outcome(
		_ url: URL?,
		_ attributes: [String: JavaScriptValue],
		into values: InlineContentPayloadValues
	) -> InlineContentOutcome {
		var values = values

		do {
			guard let html = try render(url, attributes) else { return .cancelled }

			values.html = html

			return .finished(values)
		} catch {
			return .failed(values, error as NSError)
		}
	}
}
