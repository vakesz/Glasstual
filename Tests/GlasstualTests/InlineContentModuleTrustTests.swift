import InlineContentKit
import Testing

/// A module that never declares how much its content can be trusted should get
/// the cautious answer, so forgetting to override costs a gated module rather
/// than an ungated injection point.
@Suite("Inline content module trust")
struct InlineContentModuleTrustTests {
	@Test("The base class defaults to untrusted and not safe for work")
	func baseDefaultsAreCautious() {
		#expect(InlineContentModule.contentUntrusted)
		#expect(InlineContentModule.contentNotSafeForWork)
	}

	@Test("Image and video foundations declare themselves trusted")
	func mediaFoundationsAreTrusted() {
		#expect(InlineImageFoundation.contentUntrusted == false)
		#expect(InlineImageFoundation.contentNotSafeForWork == false)
		#expect(InlineVideoFoundation.contentUntrusted == false)
		#expect(InlineVideoFoundation.contentNotSafeForWork == false)
	}

	@Test("The HTML foundation stays untrusted because it injects raw markup")
	func htmlFoundationStaysUntrusted() {
		#expect(InlineHTMLFoundation.contentUntrusted)
		#expect(InlineHTMLFoundation.contentNotSafeForWork == false)
	}
}
