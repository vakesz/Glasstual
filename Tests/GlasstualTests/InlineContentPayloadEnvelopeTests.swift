import CoreGraphics
import Foundation
import InlineContentKit
import Testing

/// The payload the inline-content service hands back is an immutable envelope
/// around a `Sendable` value; the mutable half never leaves the service. These
/// cover the seam between the two.
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

	@Test("A snapshot carries the module's edits and nothing else")
	func snapshotCarriesEdits() throws {
		let payload = try InlineContentPayloadMutable(values: Self.values())

		payload.html = "<img>"
		payload.entrypoint = "InlineImageLiveResize"
		payload.classAttribute = "inlineImageCell"
		payload.contentLength = 4096
		payload.contentSize = CGSize(width: 320, height: 240)
		payload.urlToInline = try #require(URL(string: "https://example.com/image.png"))

		let snapshot = payload.snapshot()

		#expect(snapshot.html == "<img>")
		#expect(snapshot.entrypoint == "InlineImageLiveResize")
		#expect(snapshot.classAttribute == "inlineImageCell")
		#expect(snapshot.contentLength == 4096)
		#expect(snapshot.contentSize == CGSize(width: 320, height: 240))
		#expect(snapshot.addressToInline == "https://example.com/image.png")
		#expect(snapshot.uniqueIdentifier == "unique-1")
		#expect(snapshot.viewIdentifier == "view-1")
		#expect(snapshot.lineNumber == "42")
		#expect(snapshot.index == 3)
	}

	@Test("A snapshot does not move with the payload it was taken from")
	func snapshotDoesNotFollowLaterEdits() throws {
		let payload = try InlineContentPayloadMutable(values: Self.values())

		payload.html = "first"

		let snapshot = payload.snapshot()

		payload.html = "second"

		#expect(snapshot.html == "first")
		#expect(payload.html == "second")
	}

	@Test("A deferred payload keeps the link and drops the produced content")
	func deferredPayloadKeepsOnlyTheLink() throws {
		let payload = try InlineContentPayloadMutable(values: Self.values())

		payload.classAttribute = "inlineVideoCell"
		payload.html = "<video>"
		payload.entrypoint = "entry"
		payload.scriptResources = try [#require(URL(string: "https://example.com/a.js"))]
		payload.urlToInline = try #require(URL(string: "https://example.com/clip.mp4"))

		let deferred = InlineContentPayloadMutable(deferredPayload: payload)

		#expect(deferred.uniqueIdentifier == payload.uniqueIdentifier)
		#expect(deferred.viewIdentifier == payload.viewIdentifier)
		#expect(deferred.lineNumber == payload.lineNumber)
		#expect(deferred.index == payload.index)
		#expect(deferred.classAttribute == "inlineVideoCell")
		#expect(deferred.addressToInline == "https://example.com/clip.mp4")

		#expect(deferred.html.isEmpty)
		#expect(deferred.entrypoint == nil)
		#expect(deferred.scriptResources.isEmpty)
	}

	@Test("The envelope survives secure coding, which is how it crosses XPC")
	func envelopeSurvivesSecureCoding() throws {
		let payload = try InlineContentPayloadMutable(values: Self.values())

		payload.html = "<img src=\"x\">"
		payload.entrypoint = "InlineImageLiveResize"
		payload.classAttribute = "inlineImageCell"
		payload.contentLength = 9001
		payload.contentSize = CGSize(width: 16, height: 9)
		payload.styleResources = try [#require(URL(string: "https://example.com/a.css"))]
		payload.scriptResources = try [#require(URL(string: "https://example.com/a.js"))]
		payload.urlToInline = try #require(URL(string: "https://example.com/image.png"))

		let encoded = try NSKeyedArchiver.archivedData(
			withRootObject: payload.snapshot(),
			requiringSecureCoding: true
		)
		let unarchived = try NSKeyedUnarchiver.unarchivedObject(
			ofClass: InlineContentPayload.self,
			from: encoded
		)
		let decoded = try #require(unarchived)

		#expect(decoded.values == payload.values)
	}

	@Test("The entrypoint context is derived from the values")
	func entrypointContextIsDerived() throws {
		let payload = try InlineContentPayloadMutable(values: Self.values())

		payload.html = "<img>"
		payload.classAttribute = "inlineImageCell"

		let context = payload.snapshot().entrypointPayload

		#expect(context["class"] as? String == "inlineImageCell")
		#expect(context["html"] as? String == "<img>")
		#expect(context["uniqueIdentifier"] as? String == "unique-1")
		#expect(context["lineNumber"] as? String == "42")
		#expect(context["url"] as? URL == payload.url)
		#expect(context["urlToInline"] as? URL == payload.urlToInline)
	}
}
