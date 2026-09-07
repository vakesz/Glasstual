/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf and LICENSE.txt in this directory.
 *********************************************************************** */

import CoreData
import Foundation

/// Frozen v1.0.7 archive envelope, with fixed synthetic values. This executable
/// is separate from the app, so its TVCLogLine runtime name cannot replace the app's decoder.
@objc(TVCLogLine)
final nonisolated class HistoricalLine: NSObject, NSSecureCoding { // nonisolated: immutable
	static var supportsSecureCoding: Bool {
		true
	}

	let identifier: String
	let body: String
	let date: Date

	init(identifier: String, body: String, date: Double) {
		self.identifier = identifier
		self.body = body
		self.date = Date(timeIntervalSince1970: date)
	}

	required init?(coder: NSCoder) {
		coder.failWithError(CocoaError(.coderReadCorrupt))
		return nil
	}

	func encode(with coder: NSCoder) {
		coder.encode("PRIVMSG" as NSString, forKey: "command")
		coder.encode(body as NSString, forKey: "messageBody")
		coder.encode([String](), forKey: "excludeKeywords")
		coder.encode([String](), forKey: "highlightKeywords")
		coder.encode("fixture-message-\(body)" as NSString, forKey: "messageIdentifier")
		coder.encode("fixture-parent" as NSString, forKey: "replyToMessageIdentifier")
		coder.encode(["+1": ["bob"]], forKey: "reactions")
		coder.encode("alice" as NSString, forKey: "nickname")
		coder.encode(false, forKey: "isEncrypted")
		coder.encode(false, forKey: "isFirstForDay")
		coder.encode(date, forKey: "receivedAt")
		coder.encode(17, forKey: "lineType")
		coder.encode(0, forKey: "memberType")
		coder.encode(identifier as NSString, forKey: "uniqueIdentifier")
		coder.encode(77, forKey: "sessionIdentifier")
	}
}

@main
struct GenerateHistoricalFixture {
	static func main() throws {
		guard CommandLine.arguments.count == 3,
		      let model = NSManagedObjectModel(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
		else {
			throw CocoaError(.fileReadCorruptFile)
		}
		let destination = URL(fileURLWithPath: CommandLine.arguments[2])
		guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
		let store = try coordinator.addPersistentStore(type: .sqlite, at: destination,
		                                               options: [NSSQLitePragmasOption: ["journal_mode": "DELETE"]])
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		context.persistentStoreCoordinator = coordinator
		try context.performAndWait {
			for (insertion, identifier, body, date) in [
				(1, "old", "older", 1000.0), (100, "duplicate", "duplicate-a", 2000.0),
				(100, "duplicate", "duplicate-b", 2000.0), (100, "duplicate", "duplicate-c", 2000.0),
				(9000, "new", "newer", 3000.0),
			] {
				let row = NSEntityDescription.insertNewObject(forEntityName: "LogLine2", into: context)
				let archive = try NSKeyedArchiver.archivedData(
					withRootObject: HistoricalLine(identifier: identifier, body: body, date: date),
					requiringSecureCoding: true
				)
				row.setValue(insertion, forKey: "entryIdentifier")
				row.setValue(date, forKey: "entryCreationDate")
				row.setValue(archive, forKey: "logLineData")
				row.setValue(identifier, forKey: "logLineUniqueIdentifier")
				row.setValue("v1.0.7-fixture", forKey: "logLineViewIdentifier")
				row.setValue(77, forKey: "sessionIdentifier")
			}
			try context.save()
		}
		try coordinator.remove(store)
	}
}
