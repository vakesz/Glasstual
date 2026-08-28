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

@testable import Glasstual
import Mustache
import Synchronization
import XCTest

final class ThemeTemplateStoreTests: XCTestCase {
	func testBundledDefaultTemplatesCompile() throws {
		let templatesURL = PathInfo.applicationResourcesURL
			.appending(path: ThemeResourcePath.defaultTemplates.rawValue, directoryHint: .isDirectory)
			.appending(
				path: "Version \(TPCThemeSettingsNewestTemplateEngineVersion)",
				directoryHint: .isDirectory
			)
		let templateURLs = try FileManager.default.contentsOfDirectory(
			at: templatesURL,
			includingPropertiesForKeys: nil,
			options: .skipsHiddenFiles
		).filter { $0.pathExtension == "mustache" }

		XCTAssertFalse(templateURLs.isEmpty, "The app bundle must contain its default theme templates")

		let repository = TemplateRepository(baseURL: templatesURL)
		for templateURL in templateURLs {
			let name = templateURL.deletingPathExtension().lastPathComponent
			do {
				_ = try repository.template(named: name)
			} catch let error as MustacheError {
				XCTFail(
					"Template \(name) failed with \(error.kind): " +
						"\(error.message ?? "no message") at line \(error.lineNumber.map(String.init) ?? "unknown")"
				)
			} catch {
				XCTFail("Template \(name) failed: \(String(describing: error))")
			}
		}
	}

	func testMissingOverrideFallsBackWithoutReportingAnError() throws {
		let missingOverridesURL = FileManager.default.temporaryDirectory
			.appending(path: UUID().uuidString, directoryHint: .isDirectory)
		let overrideRepository = TemplateRepository(baseURL: missingOverridesURL)
		let fallbackRepository = TemplateRepository(templates: ["message": "fallback"])
		let store = ThemeTemplateStore(
			repositories: [overrideRepository],
			fallbackRepository: fallbackRepository
		)
		let failures = Mutex<[String]>([])

		let template = try XCTUnwrap(store.template(named: "message") { error in
			failures.withLock { $0.append(String(describing: error)) }
		})

		XCTAssertEqual(try template.render(), "fallback")
		XCTAssertEqual(failures.withLock { $0 }, [])
	}

	func testConcurrentLookupWaitsUntilRecursiveTemplateCompilationFinishes() {
		let dataSource = BlockingPartialDataSource()
		let repository = TemplateRepository(dataSource: dataSource)
		let store = ThemeTemplateStore(repositories: [repository])
		let results = TemplateRenderResults()
		let lookupGroup = DispatchGroup()

		lookupGroup.enter()
		DispatchQueue.global(qos: .userInitiated).async {
			defer { lookupGroup.leave() }
			Self.renderTemplate(from: store, results: results)
		}

		XCTAssertEqual(dataSource.partialLoadStarted.wait(timeout: .now() + 2), .success)

		let secondLookupStarted = DispatchSemaphore(value: 0)
		lookupGroup.enter()
		DispatchQueue.global(qos: .userInitiated).async {
			defer { lookupGroup.leave() }
			secondLookupStarted.signal()
			Self.renderTemplate(from: store, results: results)
		}

		XCTAssertEqual(secondLookupStarted.wait(timeout: .now() + 2), .success)

		dataSource.allowPartialLoad.signal()
		XCTAssertEqual(lookupGroup.wait(timeout: .now() + 2), .success)
		XCTAssertEqual(results.failures.withLock { $0 }, [])
		XCTAssertEqual(results.renderedValues.withLock { $0.sorted() }, ["compiled", "compiled"])

		/* Two loads: "root" and "recursive-partial", each read once. The second
		 lookup arrived while the first was parked inside the partial and still
		 never reached the data source, which is what waiting for the in-flight
		 compilation means. Without that, it would have read "root" again. */
		XCTAssertEqual(dataSource.loadCount, 2)
	}

	private static func renderTemplate(
		from store: ThemeTemplateStore,
		results: TemplateRenderResults
	) {
		guard let template = store.template(named: "root", reportError: { error in
			results.failures.withLock { $0.append(error.localizedDescription) }
		}) else {
			results.failures.withLock { $0.append("Template lookup returned nil") }
			return
		}

		do {
			let rendering = try template.render()
			results.renderedValues.withLock { $0.append(rendering) }
		} catch {
			results.failures.withLock { $0.append(error.localizedDescription) }
		}
	}
}

private final class TemplateRenderResults: Sendable {
	let renderedValues = Mutex<[String]>([])
	let failures = Mutex<[String]>([])
}

private final class BlockingPartialDataSource: TemplateRepositoryDataSource, Sendable {
	let partialLoadStarted = DispatchSemaphore(value: 0)
	let allowPartialLoad = DispatchSemaphore(value: 0)
	private let loads = Mutex(0)

	var loadCount: Int {
		loads.withLock { $0 }
	}

	func templateIDForName(_ name: String, relativeToTemplateID _: TemplateID?) -> TemplateID? {
		name
	}

	func templateStringForTemplateID(_ templateID: TemplateID) throws -> String {
		loads.withLock { $0 += 1 }

		switch templateID {
		case "root":
			return "{{> recursive-partial }}"
		case "recursive-partial":
			partialLoadStarted.signal()
			guard allowPartialLoad.wait(timeout: .now() + 2) == .success else {
				throw CocoaError(.fileReadUnknown)
			}
			return "compiled"
		default:
			throw CocoaError(.fileNoSuchFile)
		}
	}
}
