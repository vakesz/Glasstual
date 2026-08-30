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
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Mustache
import os

private nonisolated let themeTemplateLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "ThemeTemplates"
)

/** Where a theme's Mustache templates are read from.

 A value, published by the theme controller alongside the rest of its snapshot,
 so a render job can build its own repositories without reaching a main-actor
 model. `generation` is bumped whenever the theme's repositories change; a cache
 that was filled under an earlier generation throws its templates away rather
 than serving one compiled from files that are no longer the theme's. */
public nonisolated struct ThemeTemplateSources: Hashable, Sendable { // nonisolated: value
	/// Template directories, most specific first.
	public let repositoryURLs: [URL]

	/// The bundled templates for the theme's engine version, searched when no
	/// theme directory has the name.
	public let fallbackURL: URL

	/// Bumped whenever the theme changes which files it renders from.
	public let generation: UInt64

	public init(repositoryURLs: [URL], fallbackURL: URL, generation: UInt64) {
		self.repositoryURLs = repositoryURLs
		self.fallbackURL = fallbackURL
		self.generation = generation
	}
}

/** One render job's compiled templates.

 `TemplateRepository` publishes a temporary, undefined syntax tree while it
 resolves recursive partials, so two renderers must never share one: exposing
 that tree to the second makes `RenderingEngine` trap on the content type it
 has not written yet. That is why this is a value with no `Sendable`
 conformance and no shared instance -- a cache belongs to the job that made it,
 lives inside one isolation domain, and dies with the job. A job renders a
 burst of lines, which is where the caching pays: the same line-type template
 is compiled once for all of them. */
nonisolated struct ThemeTemplateCache { // nonisolated: value
	/// Theme line type -> the bundled template that renders it when the theme
	/// ships no template of its own for that type.
	private nonisolated static let lineTypeFallbacks: [String: String] = // nonisolated: let
		ResourceManager
		.dictionary(fromResources: ThemeResourcePath.templateLineTypes.rawValue)?
		.compactMapValues(\.string) ?? [:]

	private var sources: ThemeTemplateSources?
	private var repositories: [TemplateRepository] = []
	private var templates: [String: Template] = [:]

	init() {}

	init(sources: ThemeTemplateSources?) {
		synchronize(with: sources)
	}

	/** Points the cache at `newSources`.

	 A different generation means the theme changed underneath the job, so
	 everything compiled so far is discarded and the repositories are rebuilt.
	 Calling it with the same sources costs one comparison. */
	mutating func synchronize(with newSources: ThemeTemplateSources?) {
		guard newSources != sources else {
			return
		}

		sources = newSources
		templates = [:]
		repositories = newSources.map { sources in
			(sources.repositoryURLs + [sources.fallbackURL]).map { TemplateRepository(baseURL: $0) }
		} ?? []
	}

	/// The compiled template called `name`, or `nil` when no repository has it.
	mutating func template(named name: String, logErrors: Bool = true) -> Template? {
		if let cached = templates[name] {
			return cached
		}

		for repository in repositories {
			do {
				let template = try repository.template(named: name)
				templates[name] = template
				return template
			} catch let error as MustacheError where error.kind == .templateNotFound {
				continue
			} catch let error as CocoaError where error.code == .fileReadNoSuchFile {
				continue
			} catch {
				guard logErrors else {
					continue
				}
				themeTemplateLogger.error(
					"""
					Failed to load template '\(name, privacy: .public)': \
					\(error.localizedDescription, privacy: .public)
					"""
				)
			}
		}

		return nil
	}

	/** The template that draws `lineType`.

	 A theme may ship `templates/line-types/<type>`; when it does not, the
	 bundled template the line-type table names is used instead. */
	mutating func template(for lineType: TVCLogLineType) -> Template? {
		guard let typeString = LogLine.string(for: lineType) else {
			return nil
		}

		let lineTypeTemplateName = "\(ThemeResourcePath.lineTypes.rawValue)/\(typeString)"
		if let template = template(named: lineTypeTemplateName, logErrors: false) {
			return template
		}

		guard let fallbackName = Self.lineTypeFallbacks[typeString] else {
			return nil
		}

		return template(named: fallbackName)
	}
}
