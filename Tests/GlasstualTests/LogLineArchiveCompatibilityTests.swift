import Foundation
@testable import Glasstual
import Testing

/** The historic log stores every line as a keyed archive whose root object is
 recorded as `TVCLogLine`. The fixture below was written by an older build and
 must keep decoding even though its obsolete renderer dictionary is ignored. */
@MainActor
struct LogLineArchiveCompatibilityTests {
	/** A fully populated line archived by an older build with secure coding. */
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
		copy.messageBody = "changed"

		#expect(line.messageBody == "hello world")
	}
}
