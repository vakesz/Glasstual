import CoreGraphics
import Foundation
import InlineContentKit
import Testing

/// The payload the inline-content service hands back is an immutable envelope
/// around a `Sendable` value; the value is what modules produce. These cover the
/// seam between the two.
@Suite("Inline content payload envelope")
struct InlineContentPayloadEnvelopeTests {
	private static func values(
		address: String = "https://example.com/page",
		view: String = "view-1"
	) throws -> InlineContentPayloadValues {
		try InlineContentPayloadValues(
			url: #require(URL(string: address)),
			uniqueIdentifier: "unique-1",
			lineNumber: "42",
			index: 3,
			viewIdentifier: view
		)
	}

	@Test("A fresh value inlines the URL it was built from")
	func freshValueInlinesItsOwnURL() throws {
		let values = try Self.values()

		#expect(values.urlToInline == values.url)
		#expect(values.html.isEmpty)
		#expect(values.entrypoint == nil)
		#expect(values.contentSize == .zero)
	}

	@Test("The envelope reads through to the value it was built from")
	func envelopeReadsThroughToItsValue() throws {
		var values = try Self.values()

		values.html = "<img>"
		values.entrypoint = "InlineImageLiveResize"
		values.classAttribute = "inlineImageCell"
		values.contentLength = 4096
		values.contentSize = CGSize(width: 320, height: 240)

		#expect(try values.setURLToInline(#require(URL(string: "https://example.com/image.png"))))

		let payload = InlineContentPayload(values: values)

		#expect(payload.html == "<img>")
		#expect(payload.entrypoint == "InlineImageLiveResize")
		#expect(payload.classAttribute == "inlineImageCell")
		#expect(payload.contentLength == 4096)
		#expect(payload.contentSize == CGSize(width: 320, height: 240))
		#expect(payload.addressToInline == "https://example.com/image.png")
		#expect(payload.uniqueIdentifier == "unique-1")
		#expect(payload.viewIdentifier == "view-1")
		#expect(payload.lineNumber == "42")
		#expect(payload.index == 3)
	}

	@Test("An envelope does not move with the value it was built from")
	func envelopeDoesNotFollowLaterEdits() throws {
		var values = try Self.values()

		values.html = "first"

		let payload = InlineContentPayload(values: values)

		values.html = "second"

		#expect(payload.html == "first")
		#expect(values.html == "second")
	}

	@Test("A deferred payload keeps the link and drops the produced content")
	func deferredPayloadKeepsOnlyTheLink() throws {
		var values = try Self.values()

		values.classAttribute = "inlineVideoCell"
		values.html = "<video>"
		values.entrypoint = "entry"
		values.scriptResources = try [#require(URL(string: "https://example.com/a.js"))]

		#expect(try values.setURLToInline(#require(URL(string: "https://example.com/clip.mp4"))))

		let deferred = values.deferredCopy

		#expect(deferred.uniqueIdentifier == values.uniqueIdentifier)
		#expect(deferred.viewIdentifier == values.viewIdentifier)
		#expect(deferred.lineNumber == values.lineNumber)
		#expect(deferred.index == values.index)
		#expect(deferred.classAttribute == "inlineVideoCell")
		#expect(deferred.urlToInline.absoluteString == "https://example.com/clip.mp4")

		#expect(deferred.html.isEmpty)
		#expect(deferred.entrypoint == nil)
		#expect(deferred.scriptResources.isEmpty)
	}

	@Test("The envelope survives secure coding, which is how it crosses XPC")
	func envelopeSurvivesSecureCoding() throws {
		var values = try Self.values()

		values.html = "<img src=\"x\">"
		values.entrypoint = "InlineImageLiveResize"
		values.classAttribute = "inlineImageCell"
		values.contentLength = 9001
		values.contentSize = CGSize(width: 16, height: 9)
		values.styleResources = try [#require(URL(string: "https://example.com/a.css"))]
		values.scriptResources = try [#require(URL(string: "https://example.com/a.js"))]

		#expect(try values.setURLToInline(#require(URL(string: "https://example.com/image.png"))))

		let encoded = try NSKeyedArchiver.archivedData(
			withRootObject: InlineContentPayload(values: values),
			requiringSecureCoding: true
		)
		let unarchived = try NSKeyedUnarchiver.unarchivedObject(
			ofClass: InlineContentPayload.self,
			from: encoded
		)
		let decoded = try #require(unarchived)

		#expect(decoded.values == values)
	}

	@Test("The entrypoint context is derived from the values")
	func entrypointContextIsDerived() throws {
		var values = try Self.values()

		values.html = "<img>"
		values.classAttribute = "inlineImageCell"

		let context = InlineContentPayload(values: values).entrypointPayload

		#expect(context["class"] as? String == "inlineImageCell")
		#expect(context["html"] as? String == "<img>")
		#expect(context["uniqueIdentifier"] as? String == "unique-1")
		#expect(context["lineNumber"] as? String == "42")
		#expect(context["url"] as? URL == values.url)
		#expect(context["urlToInline"] as? URL == values.urlToInline)
	}
}
