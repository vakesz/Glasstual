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

private enum CompilerContentType {
	case unlocked(ContentType)
	case locked(ContentType)

	var value: ContentType {
		switch self {
		case let .unlocked(contentType), let .locked(contentType):
			contentType
		}
	}
}

private enum CompilerState {
	case compiling(CompilationState)
	case error(Error)
}

private enum ScopeType {
	case root
	case section(openingToken: TemplateToken, expression: Expression)
	case invertedSection(openingToken: TemplateToken, expression: Expression)
	case partialOverride(openingToken: TemplateToken, parentPartialName: String)
	case block(openingToken: TemplateToken, blockName: String)

	var openingToken: TemplateToken? {
		switch self {
		case .root:
			nil
		case let .section(openingToken, _),
		     let .invertedSection(openingToken, _),
		     let .partialOverride(openingToken, _),
		     let .block(openingToken, _):
			openingToken
		}
	}

	var isPartialOverride: Bool {
		if case .partialOverride = self {
			true
		} else {
			false
		}
	}
}

private final class CompilationState {
	private(set) var scopeStack: [Scope]
	var compilerContentType: CompilerContentType

	var currentScope: Scope {
		scopeStack[scopeStack.endIndex - 1]
	}

	var contentType: ContentType {
		compilerContentType.value
	}

	init(contentType: ContentType) {
		compilerContentType = .unlocked(contentType)
		scopeStack = [Scope(type: .root)]
	}

	func lockContentType() {
		compilerContentType = .locked(contentType)
	}

	func popCurrentScope() {
		scopeStack.removeLast()
	}

	func pushScope(_ scope: Scope) {
		scopeStack.append(scope)
	}
}

private final class Scope {
	let type: ScopeType
	private(set) var templateASTNodes: [TemplateASTNode] = []

	init(type: ScopeType) {
		self.type = type
	}

	func appendNode(_ node: TemplateASTNode) {
		templateASTNodes.append(node)
	}
}

private enum TemplateNameKind {
	case block
	case partial

	var missingMessage: String {
		switch self {
		case .block:
			"Missing block name"
		case .partial:
			"Missing template name"
		}
	}

	var invalidMessage: String {
		switch self {
		case .block:
			"Invalid block name"
		case .partial:
			"Invalid template name"
		}
	}
}

final class TemplateCompiler: TemplateTokenConsumer {
	private var state: CompilerState
	private let repository: TemplateRepository
	private let templateID: TemplateID?

	init(contentType: ContentType, repository: TemplateRepository, templateID: TemplateID?) {
		state = .compiling(CompilationState(contentType: contentType))
		self.repository = repository
		self.templateID = templateID
	}

	func templateAST() throws -> TemplateAST {
		switch state {
		case let .compiling(compilationState):
			if let openingToken = compilationState.currentScope.type.openingToken {
				throw parseError(message: "Unclosed Mustache tag", token: openingToken)
			}
			return TemplateAST(
				nodes: compilationState.currentScope.templateASTNodes,
				contentType: compilationState.contentType
			)
		case let .error(compilationError):
			throw compilationError
		}
	}

	// MARK: - TemplateTokenConsumer

	func parser(_: TemplateParser, didFailWithError error: Error) {
		state = .error(error)
	}

	func parser(_: TemplateParser, shouldContinueAfterParsingToken token: TemplateToken) -> Bool {
		guard case let .compiling(compilationState) = state else {
			return false
		}

		do {
			try consume(token, in: compilationState)
			return true
		} catch {
			state = .error(error)
			return false
		}
	}

	// MARK: - Token compilation

	private func consume(_ token: TemplateToken, in state: CompilationState) throws {
		switch token.type {
		case .setDelimiters, .comment:
			break
		case let .pragma(content):
			try consumePragma(content, token: token, state: state)
		case let .text(text):
			consumeText(text, state: state)
		case let .escapedVariable(content, _):
			try consumeVariable(content, token: token, escapesHTML: true, state: state)
		case let .unescapedVariable(content, _):
			try consumeVariable(content, token: token, escapesHTML: false, state: state)
		case let .section(content, _):
			try openSection(content, token: token, inverted: false, state: state)
		case let .invertedSection(content, _):
			try openSection(content, token: token, inverted: true, state: state)
		case let .block(content):
			try openBlock(content, token: token, state: state)
		case let .partialOverride(content):
			try openPartialOverride(content, token: token, state: state)
		case let .close(content):
			try closeScope(content, token: token, state: state)
		case let .partial(content):
			try consumePartial(content, token: token, state: state)
		}
	}

	private func consumePragma(_ content: String, token: TemplateToken, state: CompilationState) throws {
		guard let contentType = pragmaContentType(from: content) else {
			return
		}

		switch state.compilerContentType {
		case .unlocked:
			state.compilerContentType = .unlocked(contentType)
		case .locked:
			let value = contentType == .text ? "TEXT" : "HTML"
			throw parseError(
				message: "CONTENT_TYPE:\(value) pragma tag must prepend any Mustache variable, section, or partial tag.",
				token: token
			)
		}
	}

	private func consumeText(_ text: String, state: CompilationState) {
		guard state.currentScope.type.isPartialOverride == false else {
			// Hogan.js specifies that text directly inside a partial override is ignored.
			return
		}
		state.currentScope.appendNode(.text(text: text))
	}

	private func consumeVariable(
		_ content: String,
		token: TemplateToken,
		escapesHTML: Bool,
		state: CompilationState
	) throws {
		if state.currentScope.type.isPartialOverride {
			let suffix = escapesHTML ? "." : ": \(token.templateSubstring)"
			throw parseError(message: "Illegal tag inside a partial override tag\(suffix)", token: token)
		}

		let expression = try parseExpression(content, token: token)
		state.currentScope.appendNode(.variable(
			expression: expression,
			contentType: state.contentType,
			escapesHTML: escapesHTML,
			token: token
		))
		state.lockContentType()
	}

	private func openSection(
		_ content: String,
		token: TemplateToken,
		inverted: Bool,
		state: CompilationState
	) throws {
		try rejectTagInsidePartialOverride(token, state: state)
		let expression = try parseExpression(content, token: token)
		let scopeType: ScopeType = inverted
			? .invertedSection(openingToken: token, expression: expression)
			: .section(openingToken: token, expression: expression)
		state.pushScope(Scope(type: scopeType))
		state.lockContentType()
	}

	private func openBlock(_ content: String, token: TemplateToken, state: CompilationState) throws {
		let blockName = try templateName(from: content, token: token, kind: .block)
		state.pushScope(Scope(type: .block(openingToken: token, blockName: blockName)))
		state.lockContentType()
	}

	private func openPartialOverride(_ content: String, token: TemplateToken, state: CompilationState) throws {
		let partialName = try templateName(from: content, token: token, kind: .partial)
		state.pushScope(Scope(type: .partialOverride(
			openingToken: token,
			parentPartialName: partialName
		)))
		state.lockContentType()
	}

	private func consumePartial(_ content: String, token: TemplateToken, state: CompilationState) throws {
		let partialName = try templateName(from: content, token: token, kind: .partial)
		let partialTemplateAST = try repository.templateAST(
			named: partialName,
			relativeToTemplateID: templateID
		)
		state.currentScope.appendNode(.partial(templateAST: partialTemplateAST, name: partialName))
		state.lockContentType()
	}

	// MARK: - Closing scopes

	private func closeScope(_ content: String, token: TemplateToken, state: CompilationState) throws {
		switch state.currentScope.type {
		case .root:
			throw parseError(message: "Unmatched closing tag", token: token)
		case let .section(openingToken, expression):
			try closeSection(
				content,
				token: token,
				openingToken: openingToken,
				expression: expression,
				inverted: false,
				state: state
			)
		case let .invertedSection(openingToken, expression):
			try closeSection(
				content,
				token: token,
				openingToken: openingToken,
				expression: expression,
				inverted: true,
				state: state
			)
		case let .partialOverride(_, parentPartialName):
			try closePartialOverride(content, token: token, parentPartialName: parentPartialName, state: state)
		case let .block(_, blockName):
			try closeBlock(content, token: token, blockName: blockName, state: state)
		}
	}

	private func closeSection(
		_ content: String,
		token: TemplateToken,
		openingToken: TemplateToken,
		expression: Expression,
		inverted: Bool,
		state: CompilationState
	) throws {
		let closingExpression = try optionalClosingExpression(content, token: token)
		guard closingExpression == nil || closingExpression == expression else {
			throw parseError(message: "Unmatched closing tag", token: token)
		}

		let innerTemplateAST = TemplateAST(
			nodes: state.currentScope.templateASTNodes,
			contentType: state.contentType
		)
		let innerContentRange = openingToken.range.upperBound ..< token.range.lowerBound
		let sectionNode = TemplateASTNode.section(
			templateAST: innerTemplateAST,
			expression: expression,
			inverted: inverted,
			openingToken: openingToken,
			innerTemplateString: String(token.templateString[innerContentRange])
		)
		state.popCurrentScope()
		state.currentScope.appendNode(sectionNode)
	}

	private func closePartialOverride(
		_ content: String,
		token: TemplateToken,
		parentPartialName: String,
		state: CompilationState
	) throws {
		let closingName = try optionalClosingName(content, token: token, kind: .partial)
		guard closingName == nil || closingName == parentPartialName else {
			throw parseError(message: "Unmatched closing tag", token: token)
		}

		let parentTemplateAST = try repository.templateAST(
			named: parentPartialName,
			relativeToTemplateID: templateID
		)
		try validateContentType(of: parentTemplateAST, expected: state.contentType, token: token)

		let childTemplateAST = TemplateAST(
			nodes: state.currentScope.templateASTNodes,
			contentType: state.contentType
		)
		let node = TemplateASTNode.partialOverride(
			childTemplateAST: childTemplateAST,
			parentTemplateAST: parentTemplateAST,
			parentPartialName: parentPartialName
		)
		state.popCurrentScope()
		state.currentScope.appendNode(node)
	}

	private func closeBlock(
		_ content: String,
		token: TemplateToken,
		blockName: String,
		state: CompilationState
	) throws {
		let closingName = try optionalClosingName(content, token: token, kind: .block)
		guard closingName == nil || closingName == blockName else {
			throw parseError(message: "Unmatched closing tag", token: token)
		}

		let innerTemplateAST = TemplateAST(
			nodes: state.currentScope.templateASTNodes,
			contentType: state.contentType
		)
		state.popCurrentScope()
		state.currentScope.appendNode(.block(innerTemplateAST: innerTemplateAST, name: blockName))
	}

	// MARK: - Parsing helpers

	private func pragmaContentType(from content: String) -> ContentType? {
		let components = content.split(separator: ":", omittingEmptySubsequences: false)
		guard components.count == 2 else {
			return nil
		}

		let whitespace = CharacterSet.whitespacesAndNewlines
		let name = components[0].trimmingCharacters(in: whitespace)
		let value = components[1].trimmingCharacters(in: whitespace)
		guard name == "CONTENT_TYPE" else {
			return nil
		}

		switch value {
		case "TEXT":
			return .text
		case "HTML":
			return .html
		default:
			return nil
		}
	}

	private func parseExpression(_ content: String, token: TemplateToken) throws -> Expression {
		var empty = false
		do {
			return try ExpressionParser().parse(content, empty: &empty)
		} catch let error as MustacheError {
			throw error.errorWith(templateID: token.templateID, lineNumber: token.lineNumber)
		} catch {
			throw parseError(token: token, underlyingError: error)
		}
	}

	private func optionalClosingExpression(_ content: String, token: TemplateToken) throws -> Expression? {
		var empty = false
		do {
			return try ExpressionParser().parse(content, empty: &empty)
		} catch let error as MustacheError {
			guard empty else {
				throw error.errorWith(templateID: token.templateID, lineNumber: token.lineNumber)
			}
			return nil
		} catch {
			throw parseError(token: token, underlyingError: error)
		}
	}

	private func templateName(
		from content: String,
		token: TemplateToken,
		kind: TemplateNameKind
	) throws -> String {
		var empty = false
		return try templateName(from: content, token: token, kind: kind, empty: &empty)
	}

	private func optionalClosingName(
		_ content: String,
		token: TemplateToken,
		kind: TemplateNameKind
	) throws -> String? {
		var empty = false
		do {
			return try templateName(from: content, token: token, kind: kind, empty: &empty)
		} catch {
			guard empty else {
				throw error
			}
			return nil
		}
	}

	private func templateName(
		from content: String,
		token: TemplateToken,
		kind: TemplateNameKind,
		empty: inout Bool
	) throws -> String {
		let whitespace = CharacterSet.whitespacesAndNewlines
		let name = content.trimmingCharacters(in: whitespace)
		if name.isEmpty {
			empty = true
			throw parseError(message: kind.missingMessage, token: token)
		}
		if name.rangeOfCharacter(from: whitespace) != nil {
			empty = false
			throw parseError(message: kind.invalidMessage, token: token)
		}
		return name
	}

	private func rejectTagInsidePartialOverride(_ token: TemplateToken, state: CompilationState) throws {
		guard state.currentScope.type.isPartialOverride == false else {
			throw parseError(
				message: "Illegal tag inside a partial override tag: \(token.templateSubstring)",
				token: token
			)
		}
	}

	private func validateContentType(
		of templateAST: TemplateAST,
		expected contentType: ContentType,
		token: TemplateToken
	) throws {
		guard case let .defined(_, partialContentType) = templateAST.type else {
			return
		}
		guard partialContentType == contentType else {
			throw parseError(message: "Content type mismatch", token: token)
		}
	}

	private func parseError(
		message: String? = nil,
		token: TemplateToken,
		underlyingError: Error? = nil
	) -> MustacheError {
		MustacheError(
			kind: .parseError,
			message: message,
			templateID: token.templateID,
			lineNumber: token.lineNumber,
			underlyingError: underlyingError
		)
	}
}
