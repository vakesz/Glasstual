import CocoaExtensions
import Foundation
import Testing

/// `safeFilename` turns a name a remote peer chose over DCC into a single
/// path component.
@Suite("Safe filename")
@MainActor
struct SafeFilenameTests {
	private func sanitized(_ value: String) -> String {
		value.safeFilename
	}

	@Test("Path separators are replaced")
	func separatorsAreReplaced() {
		#expect(sanitized("a/b") == "a_b")
		#expect(sanitized("a:b") == "a_b")
	}

	@Test("A traversal attempt survives as an inert name")
	func traversalIsNeutralized() {
		let result = sanitized("../../etc/passwd")

		#expect(result.contains("/") == false)
		#expect(result.hasPrefix(".") == false)
	}

	@Test("A name made only of dots cannot address a directory")
	func dotNamesAreNeutralized() {
		#expect(sanitized(".") == "_")
		#expect(sanitized("..") == "__")
	}

	@Test("A leading dot does not survive")
	func leadingDotIsReplaced() {
		#expect(sanitized(".bashrc") == "_bashrc")
	}

	@Test("Control and format characters are replaced")
	func controlCharactersAreReplaced() {
		#expect(sanitized("a\u{0}b") == "a_b")
		#expect(sanitized("a\nb") == "a_b")
		/* U+202E RIGHT-TO-LEFT OVERRIDE reverses how the rest is displayed. */
		#expect(sanitized("gpj.\u{202E}exe") == "gpj._exe")
	}

	@Test("The result fits in a path component")
	func lengthIsCapped() {
		let name = String(repeating: "a", count: 400)

		#expect(sanitized(name).utf8.count == 255)
	}

	@Test("Truncation does not split a multi-byte character")
	func truncationRespectsCharacterBoundaries() {
		/* Three UTF-8 bytes each: 255 is not a multiple of three, so a naive
		 byte cut would land inside a character. */
		let name = String(repeating: "あ", count: 200)
		let result = sanitized(name)

		#expect(result.utf8.count <= 255)
		#expect(result.allSatisfy { $0 == "あ" })
	}

	@Test("An ordinary name is left alone")
	func ordinaryNamesArePreserved() {
		#expect(sanitized("holiday photo.jpg") == "holiday photo.jpg")
	}

	@Test("Surrounding whitespace is trimmed")
	func whitespaceIsTrimmed() {
		#expect(sanitized("  report.pdf  ") == "report.pdf")
	}

	@Test("A bar is kept now that the hidden preference is gone")
	func barIsPreserved() {
		#expect(sanitized("a|b") == "a|b")
	}
}
