import Foundation
@testable import Glasstual
import Testing

/** The historic log stores every line as a keyed archive whose root object is
 recorded as `TVCLogLine`. Two fixtures below are two such archives: one written
 by an older build, which has to keep decoding, and one written by this build,
 whose bytes re-encoding has to reproduce -- otherwise every stored line churns
 the next time it is read and written back. */
@MainActor
struct LogLineArchiveCompatibilityTests {
	/** A fully populated line archived by an older build, `requiringSecureCoding:
	 true`. Its `rendererAttributes` dictionary carries an arbitrary key, which is
	 what that untyped bag allowed; the line now models only the one key the app
	 ever wrote into it, so the rest decodes and is dropped. */
	private static let fixture = [
		"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEBkLDDEy",
		"Mzg5P0NES0xNUFFSWFleX2BhZWhpVSRudWxs3xASDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkfKywtLi8wXWlzRmlyc3RGb3JEYXlacmVjZWl2ZWRB",
		"dF8QEnJlbmRlcmVyQXR0cmlidXRlc1lyZWFjdGlvbnNfEA9leGNsdWRlS2V5d29yZHNYbGluZVR5cGVdZGVsaXZlcnlTdGF0ZV8QEXNlc3Npb25JZGVudGlm",
		"aWVyWm1lbWJlclR5cGVfEBFoaWdobGlnaHRLZXl3b3Jkc1YkY2xhc3NbaXNFbmNyeXB0ZWRfEBB1bmlxdWVJZGVudGlmaWVyW21lc3NhZ2VCb2R5V2NvbW1h",
		"bmRYbmlja25hbWVfEBhyZXBseVRvTWVzc2FnZUlkZW50aWZpZXJfEBFtZXNzYWdlSWRlbnRpZmllcgmAFYAJgA+ABBAREAISAAoJSxABgAeAGAmAF4ADgAKA",
		"FIAOgA1XcHJpdm1zZ1toZWxsbyB3b3JsZNI0FzU3Wk5TLm9iamVjdHOhNoAFgAZWaWdub3Jl0jo7PD1aJGNsYXNzbmFtZVgkY2xhc3Nlc1dOU0FycmF5ojw+",
		"WE5TT2JqZWN00jQXQDehQYAIgAZVaGVsbG/TRTQXRkhKV05TLmtleXOhR4AKoUmAC4AMU2tleVV2YWx1ZdI6O05PXE5TRGljdGlvbmFyeaJOPlk2M0UxMDMz",
		"QTBZNjNFMTAzM0Ex00U0F1NVSqFUgBChVoARgAxYdGh1bWJzdXDSNBdaN6JbXIASgBOABlNib2JVY2Fyb2xVYWxpY2XSYhdjZFdOUy50aW1lI0HGQNBgAAAA",
		"gBbSOjtmZ1ZOU0RhdGWiZj5fEBE5MDhDLTU3MzVGOTM4RDY4NtI6O2prWlRWQ0xvZ0xpbmWibD5aVFZDTG9nTGluZQAIABEAGgAkACkAMgA3AEkATABRAFMA",
		"bwB1AJwAqgC1AMoA1ADmAO8A/QERARwBMAE3AUMBVgFiAWoBcwGOAaIBowGlAacBqQGrAa0BrwG0AbYBuAG6AbsBvQG/AcEBwwHFAccBzwHbAeAB6wHtAe8B",
		"8QH4Af0CCAIRAhkCHAIlAioCLAIuAjACNgI9AkUCRwJJAksCTQJPAlMCWQJeAmsCbgJ4AoICiQKLAo0CjwKRApMCnAKhAqQCpgKoAqoCrgK0AroCvwLHAtAC",
		"0gLXAt4C4QL1AvoDBQMIAAAAAAAAAgEAAAAAAAAAbQAAAAAAAAAAAAAAAAAAAxM=",
	].joined()

	private static var fixtureData: Data {
		get throws {
			try #require(Data(base64Encoded: fixture))
		}
	}

	/** The same line archived by this build. It differs from `fixture` in one
	 respect: the renderer attribute dictionary carries the one key the app
	 writes (`doNotEscapeBody`) rather than an arbitrary bag, which is what
	 ``LogLine`` now models. Keeping it as bytes rather than encoding it in the
	 test is the point — the archiver's output has to stay stable, or every
	 stored line churns the next time it is read and written back. */
	private static let currentFixture = [
		"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEBYLDC8w",
		"MTY3PUFCQ0RLTFFSU1ZXW15fVSRudWxs3xARDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnHikqKywtLl1pc0ZpcnN0Rm9yRGF5WnJlY2VpdmVkQXRZcmVh",
		"Y3Rpb25zXWRlbGl2ZXJ5U3RhdGVfEA9leGNsdWRlS2V5d29yZHNYbGluZVR5cGVfEBFzZXNzaW9uSWRlbnRpZmllclptZW1iZXJUeXBlXxARaGlnaGxpZ2h0",
		"S2V5d29yZHNWJGNsYXNzW2lzRW5jcnlwdGVkXxAQdW5pcXVlSWRlbnRpZmllclttZXNzYWdlQm9keVdjb21tYW5kWG5pY2tuYW1lXxAYcmVwbHlUb01lc3Nh",
		"Z2VJZGVudGlmaWVyXxARbWVzc2FnZUlkZW50aWZpZXIJgBKACxACgAQQERIACglLEAGAB4AVCYAUgAOAAoARgAqACVdwcml2bXNnW2hlbGxvIHdvcmxk0jIW",
		"MzVaTlMub2JqZWN0c6E0gAWABlZpZ25vcmXSODk6O1okY2xhc3NuYW1lWCRjbGFzc2VzV05TQXJyYXmiOjxYTlNPYmplY3TSMhY+NaE/gAiABlVoZWxsb1k2",
		"M0UxMDMzQTBZNjNFMTAzM0Ex00UyFkZISldOUy5rZXlzoUeADKFJgA2AEFh0aHVtYnN1cNIyFk01ok5PgA6AD4AGU2JvYlVjYXJvbNI4OVRVXE5TRGljdGlv",
		"bmFyeaJUPFVhbGljZdJYFllaV05TLnRpbWUjQcZA0GAAAACAE9I4OVxdVk5TRGF0ZaJcPF8QETkwOEMtNTczNUY5MzhENjg20jg5YGFaVFZDTG9nTGluZaJi",
		"PFpUVkNMb2dMaW5lAAgAEQAaACQAKQAyADcASQBMAFEAUwBsAHIAlwClALAAugDIANoA4wD3AQIBFgEdASkBPAFIAVABWQF0AYgBiQGLAY0BjwGRAZMBmAGa",
		"AZwBngGfAaEBowGlAacBqQGrAbMBvwHEAc8B0QHTAdUB3AHhAewB9QH9AgACCQIOAhACEgIUAhoCJAIuAjUCPQI/AkECQwJFAkcCUAJVAlgCWgJcAl4CYgJo",
		"Am0CegJ9AoMCiAKQApkCmwKgAqcCqgK+AsMCzgLRAAAAAAAAAgEAAAAAAAAAYwAAAAAAAAAAAAAAAAAAAtw=",
	].joined()

	private static var currentFixtureData: Data {
		get throws {
			try #require(Data(base64Encoded: currentFixture))
		}
	}

	@Test("An archived line decodes into every field it was written with")
	func archivedLineDecodesEveryField() throws {
		let line = try #require(LogLine(data: Self.fixtureData))

		#expect(line.command == "privmsg")
		#expect(line.lineType == .privateMessage)
		#expect(line.memberType == .localUser)
		#expect(line.deliveryState == .delivered)
		#expect(line.nickname == "alice")
		#expect(line.messageBody == "hello world")
		#expect(line.messageIdentifier == "63E1033A0")
		#expect(line.replyToMessageIdentifier == "63E1033A1")
		#expect(line.reactions == ["thumbsup": ["bob", "carol"]])
		#expect(line.highlightKeywords == ["hello"])
		#expect(line.excludeKeywords == ["ignore"])
		#expect(line.isEncrypted)
		#expect(line.isFirstForDay)
		#expect(line.receivedAt == Date(timeIntervalSince1970: 1_725_000_000))
		#expect(line.uniqueIdentifier == "908C-5735F938D686")
		#expect(line.sessionIdentifier == 657_739)
	}

	@Test("Re-encoding a decoded line reproduces the archive byte for byte")
	func reEncodingReproducesTheArchive() throws {
		let data = try Self.currentFixtureData
		let line = try #require(LogLine(data: data))

		let reEncoded = try NSKeyedArchiver.archivedData(
			withRootObject: line.archived,
			requiringSecureCoding: true
		)

		#expect(reEncoded == data)
	}

	@Test("The archive still names TVCLogLine as its root class")
	func archiveNamesTheRuntimeClass() throws {
		let text = try #require(String(data: Self.fixtureData, encoding: .isoLatin1))

		#expect(text.contains("TVCLogLine"))
	}

	@Test("A copy carries the whole line and is independent of it")
	func copyIsIndependent() throws {
		let line = try #require(LogLine(data: Self.fixtureData))
		var copy = line

		#expect(copy.uniqueIdentifier == line.uniqueIdentifier)
		#expect(copy.sessionIdentifier == line.sessionIdentifier)
		#expect(copy.nicknameColorStyle == line.nicknameColorStyle)

		copy.messageBody = "changed"

		#expect(line.messageBody == "hello world")
	}

	/** The renderer attribute dictionary is no longer an open bag: the line
	 models the one key the app ever wrote into it. An archive still carries the
	 dictionary, so a build that reads the bag reads what this one writes. */
	@Test("The one renderer attribute the app writes survives the archive")
	func doNotEscapeBodySurvivesTheArchive() throws {
		var line = LogLine()
		line.messageBody = "<b>hello</b>"
		line.doNotEscapeBody = true

		let data = try NSKeyedArchiver.archivedData(withRootObject: line.archived, requiringSecureCoding: true)
		let decoded = try #require(LogLine(data: data))

		#expect(decoded.doNotEscapeBody)

		var escaped = line
		escaped.doNotEscapeBody = false
		let escapedData = try NSKeyedArchiver.archivedData(
			withRootObject: escaped.archived,
			requiringSecureCoding: true
		)

		#expect(try #require(LogLine(data: escapedData)).doNotEscapeBody == false)
	}
}
