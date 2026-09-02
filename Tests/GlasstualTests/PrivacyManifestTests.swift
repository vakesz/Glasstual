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

import Foundation
import Testing

/** The XPC connection host ships its own privacy manifest, which App Store
 Connect aggregates with the app's. A missing manifest is silent, as is a
 manifest that declares a category the service never touches. The latter
 falsely reports an API access to the person reading the privacy report.

 So both directions are checked, by reading what the service's own sources
 call. The scan is deliberately literal: it looks for the spellings of the
 required-reason APIs, not for what the code means by them. */
@Suite("XPC service privacy manifests")
struct PrivacyManifestTests {
	/// One required-reason API category and the spellings that reach it.
	nonisolated struct Category: Sendable { // nonisolated: value
		let name: String
		let tokens: [String]

		static let all: [Category] = [
			Category(
				name: "NSPrivacyAccessedAPICategoryUserDefaults",
				tokens: ["UserDefaults"]
			),
			Category(
				name: "NSPrivacyAccessedAPICategoryFileTimestamp",
				tokens: [
					".contentModificationDateKey", ".creationDateKey", ".attributeModificationDateKey",
					".addedToDirectoryDateKey", ".fileModificationDate", ".fileCreationDate",
					"NSFileModificationDate", "NSFileCreationDate", "attributesOfItem(",
					"getattrlist", "fgetattrlist", "stat(", "fstat(", "lstat(", "fstatat(",
				]
			),
			Category(
				name: "NSPrivacyAccessedAPICategoryDiskSpace",
				tokens: [
					".volumeAvailableCapacityKey", ".volumeAvailableCapacityForImportantUsageKey",
					".volumeAvailableCapacityForOpportunisticUsageKey", ".volumeTotalCapacityKey",
					"NSFileSystemFreeSize", "NSFileSystemSize", "statfs(", "fstatfs(",
				]
			),
			Category(
				name: "NSPrivacyAccessedAPICategorySystemBootTime",
				tokens: ["systemUptime", "mach_absolute_time", "mach_continuous_time", "kern.boottime"]
			),
		]
	}

	/** The service bundle inside the app and the sources compiled into it.

	 The source list mirrors the target's `sources:` in `project.yml`. It scans
	 all of `Sources/Shared`; this is deliberately stricter than the target's
	 individual shared-file list. */
	nonisolated struct Service: Sendable, CustomStringConvertible { // nonisolated: value
		let bundleName: String
		let sourceDirectories: [String]

		var description: String {
			bundleName
		}

		static let all: [Service] = [
			Service(
				bundleName: "IRC Connection Host.xpc",
				sourceDirectories: [
					"Sources/Services/IRC Connection Host",
					"Sources/Shared",
				]
			),
		]
	}

	// MARK: - The bundles

	@Test("Every XPC service in the app carries a privacy manifest")
	func everyServiceCarriesAManifest() throws {
		let services = try Self.bundledServiceNames()

		#expect(
			services == Set(Service.all.map(\.bundleName)),
			"the services in the app do not match the ones this suite audits"
		)

		for name in services.sorted() {
			let manifest = try Self.manifest(forServiceNamed: name)

			#expect(manifest["NSPrivacyTracking"] as? Bool == false, "\(name) declares tracking")
			#expect(manifest["NSPrivacyTrackingDomains"] as? [String] == [], "\(name) declares tracking domains")
			#expect(
				manifest["NSPrivacyCollectedDataTypes"] is [Any],
				"\(name) is missing NSPrivacyCollectedDataTypes"
			)
		}
	}

	@Test("Every declared reason code is well formed", arguments: Service.all)
	func reasonCodesAreWellFormed(service: Service) throws {
		let declared = try Self.accessedAPITypes(forServiceNamed: service.bundleName)

		for (category, reasons) in declared {
			#expect(reasons.isEmpty == false, "\(service) declares \(category) with no reason")

			for reason in reasons {
				#expect(
					reason.wholeMatch(of: /[0-9A-F]{4}\.\d+/) != nil,
					"\(service) declares \(reason) for \(category), which is not a reason code"
				)
			}
		}
	}

	// MARK: - The audit

	@Test(
		"A service declares every required-reason category its sources reach, and no other",
		arguments: Service.all
	)
	func declaredCategoriesMatchTheSources(service: Service) throws {
		let declared = try Set(Self.accessedAPITypes(forServiceNamed: service.bundleName).keys)
		let sources = try Self.swiftSources(in: service.sourceDirectories)

		#expect(sources.isEmpty == false, "\(service) has no sources to audit")

		var reached: Set<String> = []

		for category in Category.all where sources.contains(where: { code in
			category.tokens.contains { code.contains($0) }
		}) {
			reached.insert(category.name)
		}

		#expect(
			reached.subtracting(declared).sorted() == [],
			"\(service) reaches a required-reason API its manifest does not declare"
		)
		#expect(
			declared.subtracting(reached).sorted() == [],
			"\(service) declares a required-reason API its sources never call"
		)
	}

	// MARK: - Helpers

	private static var repositoryRoot: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}

	private static func bundledServiceNames() throws -> Set<String> {
		let directory = Bundle.main.bundleURL
			.appending(path: "Contents")
			.appending(path: "XPCServices")

		let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

		return Set(contents.filter { $0.pathExtension == "xpc" }.map(\.lastPathComponent))
	}

	private static func manifest(forServiceNamed name: String) throws -> [String: Any] {
		let url = Bundle.main.bundleURL
			.appending(path: "Contents")
			.appending(path: "XPCServices")
			.appending(path: name)
			.appending(path: "Contents")
			.appending(path: "Resources")
			.appending(path: "PrivacyInfo.xcprivacy")

		let data = try #require(
			try? Data(contentsOf: url),
			"\(name) ships no PrivacyInfo.xcprivacy"
		)

		let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

		return try #require(plist as? [String: Any], "\(name) has a malformed privacy manifest")
	}

	/// Category name to the reasons declared for it.
	private static func accessedAPITypes(forServiceNamed name: String) throws -> [String: [String]] {
		let manifest = try manifest(forServiceNamed: name)
		let entries = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []

		var result: [String: [String]] = [:]

		for entry in entries {
			guard let category = entry["NSPrivacyAccessedAPIType"] as? String else {
				Issue.record("\(name) has an entry with no NSPrivacyAccessedAPIType")
				continue
			}

			result[category] = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
		}

		return result
	}

	/// The Swift under each directory, with line comments removed so that prose
	/// about an API is not read as a call to it.
	private static func swiftSources(in directories: [String]) throws -> [String] {
		var sources: [String] = []

		for directory in directories {
			let url = repositoryRoot.appending(path: directory)

			guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
				Issue.record("\(directory) could not be walked")
				continue
			}

			for case let file as URL in walker where file.pathExtension == "swift" {
				try sources.append(strippingComments(String(contentsOf: file, encoding: .utf8)))
			}
		}

		return sources
	}

	/** Line and block comments removed. Nested block comments, and a block
	 comment opener inside a string literal, are not modelled -- the same limit
	 the isolation gate takes, and no source in the tree relies on either. */
	private static func strippingComments(_ source: String) -> String {
		var result = ""
		let characters = Array(source)
		var index = 0
		var inBlock = false

		while index < characters.count {
			let pair = index + 1 < characters.count ? String(characters[index ... index + 1]) : ""

			if inBlock {
				if pair == "*/" {
					inBlock = false
					index += 2
				} else {
					index += 1
				}
			} else if pair == "/*" {
				inBlock = true
				index += 2
			} else if pair == "//" {
				while index < characters.count, characters[index] != "\n" {
					index += 1
				}
			} else {
				result.append(characters[index])
				index += 1
			}
		}

		return result
	}
}
