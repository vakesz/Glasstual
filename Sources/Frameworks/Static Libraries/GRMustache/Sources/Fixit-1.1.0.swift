// The MIT License
//
// Copyright (c) 2015 Gwendal Roué
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

@available(*, unavailable, message: "Use nil instead.")
public func makeMustacheBox() -> MustacheBox {
	.empty
}

public extension Template {
	@available(*, unavailable, renamed: "register(_:forKey:)")
	func registerInBaseContext(_: String, _: Any?) {}
}

public extension Context {
	@available(*, unavailable, renamed: "mustacheBox(forKey:)")
	func mustacheBoxForKey(_: String) -> MustacheBox {
		.empty
	}

	@available(*, unavailable, renamed: "mustacheBox(forExpression:)")
	func mustacheBoxForExpression(_: String) throws -> MustacheBox {
		.empty
	}

	@available(*, unavailable, renamed: "extendedContext(withRegisteredValue:forKey:)")
	internal func contextWithRegisteredKey(_: String, box _: MustacheBox) -> Context {
		self
	}
}

public extension MustacheBox {
	@nonobjc @available(*, unavailable, renamed: "mustacheBox(forKey:)")
	func mustacheBoxForKey(_: String) -> MustacheBox {
		.empty
	}
}
