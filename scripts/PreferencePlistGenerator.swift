/* The entry point of the tool `scripts/generate-preference-plists.sh` builds.
 It is compiled together with the preference declarations themselves, so the
 plists it writes cannot describe anything the code does not declare.

 One argument: the directory the plists are written into. */

import CocoaExtensions
import Foundation

@main
enum PreferencePlistGenerator {
	private static var resources: [(name: String, contents: [String: PropertyListValue])] {
		[
			("KeysExcludedFromContainer", Preferences.GeneratedResources.keysExcludedFromContainer),
			("KeysExcludedFromExport", Preferences.GeneratedResources.keysExcludedFromExport),
			("PreferenceKeyMasterList", Preferences.GeneratedResources.keyCatalog),
			("RegisteredUserDefaults", Preferences.GeneratedResources.registeredUserDefaults),
			("RegisteredUserDefaultsInContainer", Preferences.GeneratedResources.registeredUserDefaultsInContainer),
		]
	}

	static func main() {
		guard CommandLine.arguments.count == 2 else {
			fail("usage: \(CommandLine.arguments.first ?? "tool") <output-directory>")
		}

		let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

		for resource in resources {
			write(resource.contents, named: resource.name, into: directory)
		}
	}

	private static func write(_ contents: [String: PropertyListValue], named name: String, into directory: URL) {
		let url = directory.appendingPathComponent("\(name).plist")

		let data: Data
		do {
			data = try PropertyListSerialization.data(
				fromPropertyList: contents.propertyListObject,
				format: .xml,
				options: 0
			)
		} catch {
			fail("could not serialise \(name): \(error)")
		}

		// Rewriting an unchanged file would touch its modification date, and
		// this runs as a build phase on every build of the application.
		if let existing = try? Data(contentsOf: url), existing == data {
			return
		}

		do {
			// Not atomic: a build phase is sandboxed to the files it declared
			// as outputs, and the rename an atomic write goes through needs a
			// second file beside them.
			try data.write(to: url, options: [])
		} catch {
			fail("could not write \(url.path): \(error)")
		}

		print("wrote \(name).plist")
	}

	private static func fail(_ message: String) -> Never {
		FileHandle.standardError.write(Data("generate-preference-plists: \(message)\n".utf8))
		exit(1)
	}
}
