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
@testable import Glasstual
import Mustache
import Testing

/// Nonisolated: the cache is, and the concurrency tests below run render jobs
/// off the main actor the way the pipeline does.
@Suite("Theme template cache")
nonisolated struct ThemeTemplateCacheTests {
	/// The directory of templates the application ships for the current engine
	/// version, which is what a theme falls back to.
	private static func bundledDefaultTemplatesURL() throws -> URL {
		PathInfo.applicationResourcesURL
			.appending(path: ThemeResourcePath.defaultTemplates.rawValue, directoryHint: .isDirectory)
			.appending(
				path: "Version \(TPCThemeSettingsNewestTemplateEngineVersion)",
				directoryHint: .isDirectory
			)
	}

	@Test("Every default template the app bundles compiles")
	func bundledDefaultTemplatesCompile() throws {
		let templatesURL = try Self.bundledDefaultTemplatesURL()
		let templateURLs = try FileManager.default.contentsOfDirectory(
			at: templatesURL,
			includingPropertiesForKeys: nil,
			options: .skipsHiddenFiles
		).filter { $0.pathExtension == "mustache" }

		#expect(templateURLs.isEmpty == false, "The app bundle must contain its default theme templates")

		var cache = ThemeTemplateCache(sources: ThemeTemplateSources(
			repositoryURLs: [],
			fallbackURL: templatesURL,
			generation: 1
		))

		for templateURL in templateURLs {
			let name = templateURL.deletingPathExtension().lastPathComponent

			if cache.template(named: name) == nil {
				Issue.record("Template \(name) did not compile")
			}
		}
	}

	/** The line-type table is a bundled property list the cache reads at
	 runtime, so nothing in the compiler notices when it comes back empty --
	 and an empty table means every line whose theme ships no override of its
	 own renders to nothing at all. That is what happened when the resource
	 reader started handing back a typed value and the cast above it kept
	 asking for `[String: String]`. */
	@Test(
		"Every line type a theme does not override resolves the bundled template",
		arguments: [
			TVCLogLineType.privateMessage,
			.action,
			.notice,
			.join,
			.part,
			.quit,
			.topic,
			.mode,
			.kick,
			.nick,
			.debug,
		]
	)
	func everyLineTypeResolvesItsBundledTemplate(lineType: TVCLogLineType) throws {
		var cache = try ThemeTemplateCache(sources: ThemeTemplateSources(
			repositoryURLs: [],
			fallbackURL: Self.bundledDefaultTemplatesURL(),
			generation: 1
		))

		#expect(cache.template(for: lineType) != nil)
	}

	@Test("A theme that overrides nothing falls back to the bundled template")
	func missingOverrideFallsBackToTheFallbackRepository() throws {
		let overrides = try Self.makeTemplateDirectory(templates: [:])
		let fallback = try Self.makeTemplateDirectory(templates: ["message": "fallback"])
		defer { Self.remove(overrides, fallback) }

		var cache = ThemeTemplateCache(sources: ThemeTemplateSources(
			repositoryURLs: [overrides],
			fallbackURL: fallback,
			generation: 1
		))

		let found = cache.template(named: "message")
		let template = try #require(found)

		#expect(try template.render() == "fallback")
	}

	/** The point of the per-job cache. Two jobs render a template of the same
	 name at the same time from two different themes; with a shared store the
	 second would have been handed the first one's compiled template. */
	@Test("Two concurrent render jobs render their own theme's template")
	func concurrentJobsDoNotShareCompiledTemplates() async throws {
		let firstTheme = try Self.makeTemplateDirectory(templates: ["message": "first {{body}}"])
		let secondTheme = try Self.makeTemplateDirectory(templates: ["message": "second {{body}}"])
		defer { Self.remove(firstTheme, secondTheme) }

		let first = ThemeTemplateSources(repositoryURLs: [firstTheme], fallbackURL: firstTheme, generation: 1)
		let second = ThemeTemplateSources(repositoryURLs: [secondTheme], fallbackURL: secondTheme, generation: 2)

		let rendered = await withTaskGroup(of: [String].self) { group in
			for job in 0 ..< 8 {
				let sources = job.isMultiple(of: 2) ? first : second
				group.addTask {
					var cache = ThemeTemplateCache(sources: sources)
					return (0 ..< 20).map { _ in
						guard let template = cache.template(named: "message") else {
							return "missing"
						}
						return (try? template.render(["body": "hello"])) ?? "failed"
					}
				}
			}

			var collected: [[String]] = []
			for await job in group {
				collected.append(job)
			}
			return collected
		}

		#expect(rendered.count == 8)

		for job in rendered {
			#expect(job.count == 20)
			// Every render in one job saw one theme, and only one.
			#expect(Set(job).count == 1)
			#expect(job[0] == "first hello" || job[0] == "second hello")
		}

		let texts = Set(rendered.map { $0[0] })

		#expect(texts == ["first hello", "second hello"])
	}

	@Test("A theme generation bump makes the cache recompile")
	func generationBumpDiscardsTheCompiledTemplates() throws {
		let before = try Self.makeTemplateDirectory(templates: ["message": "before"])
		let after = try Self.makeTemplateDirectory(templates: ["message": "after"])
		defer { Self.remove(before, after) }

		var cache = ThemeTemplateCache()
		cache.synchronize(with: ThemeTemplateSources(
			repositoryURLs: [before],
			fallbackURL: before,
			generation: 7
		))

		let foundBefore = cache.template(named: "message")
		let beforeTemplate = try #require(foundBefore)

		#expect(try beforeTemplate.render() == "before")

		cache.synchronize(with: ThemeTemplateSources(
			repositoryURLs: [after],
			fallbackURL: after,
			generation: 8
		))

		let foundAfter = cache.template(named: "message")
		let afterTemplate = try #require(foundAfter)

		#expect(try afterTemplate.render() == "after")
	}

	@Test("A cache with no sources finds nothing rather than trapping")
	func cacheWithoutSourcesFindsNothing() {
		var cache = ThemeTemplateCache()

		#expect(cache.template(named: "message") == nil)
		#expect(cache.template(for: .privateMessage) == nil)
	}

	/// Writes `templates` as `<name>.mustache` files in a fresh directory.
	private static func makeTemplateDirectory(templates: [String: String]) throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appending(path: "glasstual-templates-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		for (name, contents) in templates {
			try contents.write(
				to: directory.appending(path: "\(name).mustache"),
				atomically: true,
				encoding: .utf8
			)
		}

		return directory
	}

	private static func remove(_ directories: URL...) {
		for directory in directories {
			try? FileManager.default.removeItem(at: directory)
		}
	}
}
