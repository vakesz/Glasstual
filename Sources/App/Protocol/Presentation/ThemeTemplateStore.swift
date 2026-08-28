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

import Foundation
import Mustache
import Synchronization

/// Owns the synchronous boundary around GRMustache's mutable repository cache.
///
/// `TemplateRepository` publishes a temporary, undefined syntax tree while it
/// resolves recursive partials. Repository lookup and compilation must therefore
/// remain one transaction: exposing that temporary tree to another rendering
/// queue causes `RenderingEngine` to trap when it reads the missing content type.
final nonisolated class ThemeTemplateStore: Sendable {
	/// Mustache's reference types predate Swift concurrency. Every reference in
	/// this state is created, replaced, and used only while `state` is locked.
	/* ISOLATION-EXCEPTION: `TemplateRepository` comes from GRMustache and is not
	 `Sendable`. The state only ever leaves this type inside its `Mutex`. */
	private struct State: @unchecked Sendable {
		let cache = NSCache<NSString, Template>()
		var repositories: [TemplateRepository]
		var fallbackRepository: TemplateRepository?
	}

	private let state: Mutex<State>

	init(
		repositories: [TemplateRepository] = [],
		fallbackRepository: TemplateRepository? = nil
	) {
		state = Mutex(State(repositories: repositories, fallbackRepository: fallbackRepository))
	}

	func replaceRepositories(
		_ repositories: [TemplateRepository],
		fallbackRepository: TemplateRepository?
	) {
		state.withLock { state in
			state.cache.removeAllObjects()
			state.repositories = repositories
			state.fallbackRepository = fallbackRepository
		}
	}

	func template(
		named name: String,
		reportError: (any Error) -> Void
	) -> Template? {
		state.withLock { state in
			if let cached = state.cache.object(forKey: name as NSString) {
				return cached
			}

			let repositories = state.repositories + [state.fallbackRepository].compactMap(\.self)
			for repository in repositories {
				do {
					let template = try repository.template(named: name)
					state.cache.setObject(template, forKey: name as NSString)
					return template
				} catch let error as MustacheError where error.kind == .templateNotFound {
					continue
				} catch let error as CocoaError where error.code == .fileReadNoSuchFile {
					continue
				} catch {
					reportError(error)
				}
			}

			return nil
		}
	}
}
