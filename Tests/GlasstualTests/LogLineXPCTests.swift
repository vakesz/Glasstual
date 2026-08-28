import Foundation
@testable import Glasstual
import Testing

/// `LogLineXPC` is the wire format between the app and the historic-log
/// service, so it has to survive a hostile archive without trapping.
@Suite("Log line XPC transfer object")
@MainActor
struct LogLineXPCTests {
	private static let keys = (
		data: "data",
		uniqueIdentifier: "uniqueIdentifier",
		viewIdentifier: "viewIdentifier",
		sessionIdentifier: "sessionIdentifier",
		creationDate: "entryCreationDate"
	)

	private static func archive(sessionIdentifier: Int, creationDate: Double) -> Data {
		let archiver = NSKeyedArchiver(requiringSecureCoding: true)
		archiver.encode(Data([0x01]), forKey: keys.data)
		archiver.encode("line-1" as NSString, forKey: keys.uniqueIdentifier)
		archiver.encode("view-1" as NSString, forKey: keys.viewIdentifier)
		archiver.encode(sessionIdentifier, forKey: keys.sessionIdentifier)
		archiver.encode(creationDate, forKey: keys.creationDate)
		archiver.finishEncoding()
		return archiver.encodedData
	}

	private static func decode(_ data: Data) throws -> LogLineXPC? {
		let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
		unarchiver.requiresSecureCoding = true
		defer { unarchiver.finishDecoding() }
		return LogLineXPC(coder: unarchiver)
	}

	/// The write-path initialiser used to hardcode zero, so everything written
	/// in a session was stamped 1970 on the way across.
	@Test("The creation date given on the write path is the one that is sent")
	func creationDateSurvivesTheWritePath() throws {
		let now = Date().timeIntervalSince1970
		let object = LogLineXPC(
			logLineData: Data([0x01]),
			uniqueIdentifier: "line-1",
			viewIdentifier: "view-1",
			sessionIdentifier: 7,
			creationDate: now
		)

		#expect(object.creationDate == now)

		let encoded = try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: true)
		let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: LogLineXPC.self, from: encoded)

		#expect(decoded?.creationDate == now)
		#expect(decoded?.sessionIdentifier == 7)
		#expect(decoded?.uniqueIdentifier == "line-1")
	}

	/// `UInt(coder.decodeInteger(...))` trapped instead of failing the decode.
	@Test("A negative session identifier fails the decode instead of trapping")
	func negativeSessionIdentifierIsRefused() throws {
		let decoded = try Self.decode(Self.archive(sessionIdentifier: -1, creationDate: 0))
		#expect(decoded == nil)
	}

	@Test("A non-finite or negative creation date fails the decode", arguments: [
		-1.0,
		Double.infinity,
		Double.nan,
	])
	func unusableCreationDateIsRefused(creationDate: Double) throws {
		let decoded = try Self.decode(Self.archive(sessionIdentifier: 1, creationDate: creationDate))
		#expect(decoded == nil)
	}

	@Test("A well-formed archive still decodes")
	func wellFormedArchiveDecodes() throws {
		let decoded = try Self.decode(Self.archive(sessionIdentifier: 3, creationDate: 1_700_000_000))
		#expect(decoded?.sessionIdentifier == 3)
		#expect(decoded?.creationDate == 1_700_000_000)
	}
}
