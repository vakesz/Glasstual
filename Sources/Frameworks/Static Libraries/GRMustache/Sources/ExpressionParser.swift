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

import Foundation

final class ExpressionParser {
	private enum State {
		case error(String)
		case waitingForAnyExpression
		case leadingDot
		case identifier(start: String.Index)
		case scopingIdentifier(start: String.Index, base: Expression)
		case waitingForScopingIdentifier(base: Expression)
		case done(Expression)
		case doneAfterWhitespace(Expression)
	}

	private enum FinalState {
		case error(String)
		case empty
		case valid(Expression)
	}

	func parse(_ string: String, empty outEmpty: inout Bool) throws -> Expression {
		var state = State.waitingForAnyExpression
		var filterStack: [Expression] = []
		var index = string.startIndex

		while index < string.endIndex {
			state = transition(
				from: state,
				character: string[index],
				at: index,
				in: string,
				filterStack: &filterStack
			)
			if case .error = state {
				break
			}
			index = string.index(after: index)
		}

		switch finalState(for: state, filterStack: filterStack, in: string) {
		case .empty:
			outEmpty = true
			throw MustacheError(kind: .parseError, message: "Missing expression")
		case let .error(description):
			outEmpty = false
			throw MustacheError(kind: .parseError, message: "Invalid expression `\(string)`: \(description)")
		case let .valid(expression):
			return expression
		}
	}

	private func transition(
		from state: State,
		character: Character,
		at index: String.Index,
		in string: String,
		filterStack: inout [Expression]
	) -> State {
		switch state {
		case .error:
			state
		case .waitingForAnyExpression:
			transitionFromWaiting(character, at: index, in: string)
		case .leadingDot:
			transitionFromLeadingDot(character, at: index, in: string, filterStack: &filterStack)
		case let .identifier(start):
			transitionFromIdentifier(
				character,
				start: start,
				at: index,
				in: string,
				filterStack: &filterStack
			)
		case let .scopingIdentifier(start, base):
			transitionFromScopingIdentifier(
				character,
				start: start,
				base: base,
				at: index,
				in: string,
				filterStack: &filterStack
			)
		case let .waitingForScopingIdentifier(base):
			transitionFromWaitingForScope(character, base: base, at: index, in: string)
		case let .done(expression):
			transitionFromDone(
				character,
				expression: expression,
				afterWhitespace: false,
				at: index,
				in: string,
				filterStack: &filterStack
			)
		case let .doneAfterWhitespace(expression):
			transitionFromDone(
				character,
				expression: expression,
				afterWhitespace: true,
				at: index,
				in: string,
				filterStack: &filterStack
			)
		}
	}

	private func transitionFromWaiting(
		_ character: Character,
		at index: String.Index,
		in string: String
	) -> State {
		if character.isWhitespace {
			return .waitingForAnyExpression
		}
		if character == "." {
			return .leadingDot
		}
		if isReserved(character) {
			return unexpected(character, at: index, in: string)
		}
		return .identifier(start: index)
	}

	private func transitionFromLeadingDot(
		_ character: Character,
		at index: String.Index,
		in string: String,
		filterStack: inout [Expression]
	) -> State {
		if character.isWhitespace {
			return .doneAfterWhitespace(.implicitIterator)
		}
		switch character {
		case ".":
			return unexpected(character, at: index, in: string)
		case "(":
			filterStack.append(.implicitIterator)
			return .waitingForAnyExpression
		case ")":
			return closeFilter(
				argument: .implicitIterator,
				character: character,
				at: index,
				in: string,
				stack: &filterStack
			)
		case ",":
			return continueFilter(
				argument: .implicitIterator,
				character: character,
				at: index,
				in: string,
				stack: &filterStack
			)
		default:
			if isReserved(character) {
				return unexpected(character, at: index, in: string)
			}
			return .scopingIdentifier(start: index, base: .implicitIterator)
		}
	}

	private func transitionFromIdentifier(
		_ character: Character,
		start: String.Index,
		at index: String.Index,
		in string: String,
		filterStack: inout [Expression]
	) -> State {
		let expression = Expression.identifier(identifier: String(string[start ..< index]))
		if character.isWhitespace {
			return .doneAfterWhitespace(expression)
		}
		switch character {
		case ".":
			return .waitingForScopingIdentifier(base: expression)
		case "(":
			filterStack.append(expression)
			return .waitingForAnyExpression
		case ")":
			return closeFilter(argument: expression, character: character, at: index, in: string, stack: &filterStack)
		case ",":
			return continueFilter(
				argument: expression,
				character: character,
				at: index,
				in: string,
				stack: &filterStack
			)
		default:
			return .identifier(start: start)
		}
	}

	private func transitionFromScopingIdentifier(
		_ character: Character,
		start: String.Index,
		base: Expression,
		at index: String.Index,
		in string: String,
		filterStack: inout [Expression]
	) -> State {
		let identifier = String(string[start ..< index])
		let expression = Expression.scoped(baseExpression: base, identifier: identifier)
		if character.isWhitespace {
			return .doneAfterWhitespace(expression)
		}
		switch character {
		case ".":
			return .waitingForScopingIdentifier(base: expression)
		case "(":
			filterStack.append(expression)
			return .waitingForAnyExpression
		case ")":
			return closeFilter(argument: expression, character: character, at: index, in: string, stack: &filterStack)
		case ",":
			return continueFilter(
				argument: expression,
				character: character,
				at: index,
				in: string,
				stack: &filterStack
			)
		default:
			return .scopingIdentifier(start: start, base: base)
		}
	}

	private func transitionFromWaitingForScope(
		_ character: Character,
		base: Expression,
		at index: String.Index,
		in string: String
	) -> State {
		if character.isWhitespace {
			return .error("Unexpected white space character at index \(offset(of: index, in: string))")
		}
		if isReserved(character) || character == "." {
			return unexpected(character, at: index, in: string)
		}
		return .scopingIdentifier(start: index, base: base)
	}

	private func transitionFromDone(
		_ character: Character,
		expression: Expression,
		afterWhitespace: Bool,
		at index: String.Index,
		in string: String,
		filterStack: inout [Expression]
	) -> State {
		if character.isWhitespace {
			return .doneAfterWhitespace(expression)
		}
		switch character {
		case "." where !afterWhitespace:
			return .waitingForScopingIdentifier(base: expression)
		case "(":
			filterStack.append(expression)
			return .waitingForAnyExpression
		case ")":
			return closeFilter(argument: expression, character: character, at: index, in: string, stack: &filterStack)
		case ",":
			return continueFilter(
				argument: expression,
				character: character,
				at: index,
				in: string,
				stack: &filterStack
			)
		default:
			return unexpected(character, at: index, in: string)
		}
	}

	private func closeFilter(
		argument: Expression,
		character: Character,
		at index: String.Index,
		in string: String,
		stack: inout [Expression]
	) -> State {
		guard let filterExpression = stack.popLast() else {
			return unexpected(character, at: index, in: string)
		}
		return .done(.filter(
			filterExpression: filterExpression,
			argumentExpression: argument,
			partialApplication: false
		))
	}

	private func continueFilter(
		argument: Expression,
		character: Character,
		at index: String.Index,
		in string: String,
		stack: inout [Expression]
	) -> State {
		guard let filterExpression = stack.popLast() else {
			return unexpected(character, at: index, in: string)
		}
		stack.append(.filter(
			filterExpression: filterExpression,
			argumentExpression: argument,
			partialApplication: true
		))
		return .waitingForAnyExpression
	}

	private func finalState(
		for state: State,
		filterStack: [Expression],
		in string: String
	) -> FinalState {
		if case let .error(message) = state {
			return .error(message)
		}
		if !filterStack.isEmpty {
			return .error("Missing `)` character at index \(string.count)")
		}

		switch state {
		case .waitingForAnyExpression:
			return .empty
		case .leadingDot:
			return .valid(.implicitIterator)
		case let .identifier(start):
			return .valid(.identifier(identifier: String(string[start...])))
		case let .scopingIdentifier(start, base):
			return .valid(.scoped(baseExpression: base, identifier: String(string[start...])))
		case .waitingForScopingIdentifier:
			return .error("Missing identifier at index \(string.count)")
		case let .done(expression), let .doneAfterWhitespace(expression):
			return .valid(expression)
		case let .error(message):
			return .error(message)
		}
	}

	private func unexpected(
		_ character: Character,
		at index: String.Index,
		in string: String
	) -> State {
		.error("Unexpected character `\(character)` at index \(offset(of: index, in: string))")
	}

	private func offset(of index: String.Index, in string: String) -> Int {
		string.distance(from: string.startIndex, to: index)
	}

	private func isReserved(_ character: Character) -> Bool {
		["(", ")", ",", "{", "}", "&", "$", "#", "^", "/", "<", ">"].contains(character)
	}
}
