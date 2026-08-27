// The MIT License
//
// Copyright (c) 2014 Gwendal Roué
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

/// The compatibility functions that Objective-C GRMustache installed in every
/// template context. Glasstual themes use `isEmpty`, and third-party themes may
/// rely on the remaining documented GRMustache 7 functions.
enum LegacyStandardLibrary {
	static func values() -> [String: Any] {
		[
			"capitalized": stringFilter { $0.capitalized },
			"lowercase": stringFilter { $0.lowercased() },
			"uppercase": stringFilter { $0.uppercased() },
			"isBlank": filter(isBlank),
			"isEmpty": filter(isEmpty),
			"localize": StandardLibrary.Localizer(),
			"each": StandardLibrary.each,
			"HTML": ["escape": StandardLibrary.HTMLEscape],
			"javascript": ["escape": StandardLibrary.javascriptEscape],
			"URL": ["escape": StandardLibrary.URLEscape],
		]
	}

	private static func stringFilter(_ transform: @escaping (String) -> String) -> FilterFunction {
		filter { box in
			guard let value = box.value, !(value is NSNull) else { return "" }
			return transform(String(describing: value))
		}
	}

	private static func isBlank(_ box: MustacheBox) -> Bool {
		guard !isNilOrNull(box) else { return true }
		if box.dictionaryValue == nil, let values = box.arrayValue {
			return values.isEmpty
		}
		return renderedDescription(of: box)
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.isEmpty
	}

	private static func isEmpty(_ box: MustacheBox) -> Bool {
		guard !isNilOrNull(box) else { return true }
		if box.dictionaryValue == nil, let values = box.arrayValue {
			return values.isEmpty
		}
		return renderedDescription(of: box).isEmpty
	}

	private static func isNilOrNull(_ box: MustacheBox) -> Bool {
		box.isEmpty || box.value is NSNull
	}

	private static func renderedDescription(of box: MustacheBox) -> String {
		box.value.map { String(describing: $0) } ?? ""
	}
}
