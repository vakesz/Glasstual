/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers

@Suite("Bounded native inline media", .serialized)
@MainActor
struct NativeInlineImageLoaderTests {
	@Test("Static decoding downsamples, applies orientation and preserves the colour profile")
	func orientedStaticPreview() async throws {
		let data = try Self.stillImage(width: 80, height: 40, orientation: 6)
		var limits = NativeInlineImageLimits()
		limits.thumbnailDimension = 32
		let preview = try await NativeInlineImageDecoder.prepare(data, limits: limits)
		let source = try #require(CGImageSourceCreateWithData(preview.data as CFData, nil))
		let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
		#expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
		#expect(image.width == 16)
		#expect(image.height == 32)
		#expect(image.colorSpace?.name == CGColorSpace.displayP3)
		#expect(preview.residentByteCount >= image.bytesPerRow * image.height + preview.data.count)
	}

	@Test("GIF bytes preserve unequal delays, looping, transparency and restore disposal")
	func animationIsNotFlattened() async throws {
		let data = Self.gif(frames: 2)
		let expectedRepeatCount: UInt16 = 3
		let expectedPlayCount = 4
		// The fixture's NETSCAPE2.0 field stores repeats after the initial play,
		// unlike APNG's num_plays. ImageIO reports the total number of plays.
		let extensionRange = try #require(data.range(of: Data("NETSCAPE2.0".utf8)))
		let repeatOffset = extensionRange.upperBound + 2 // Sub-block length and identifier.
		#expect(UInt16(data[repeatOffset]) | UInt16(data[repeatOffset + 1]) << 8 == expectedRepeatCount)
		let inputSource = try #require(CGImageSourceCreateWithData(data as CFData, nil))
		let inputProperties = try #require(CGImageSourceCopyProperties(inputSource, nil) as? [CFString: Any])
		let inputGIF = try #require(inputProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
		let inputPlayCount = try #require((inputGIF[kCGImagePropertyGIFLoopCount] as? NSNumber)?.intValue)
		#expect(inputPlayCount == expectedPlayCount)
		let preview = try await NativeInlineImageDecoder.prepare(data, limits: .init())
		#expect(preview.data == data)
		let source = try #require(CGImageSourceCreateWithData(preview.data as CFData, nil))
		#expect(CGImageSourceGetCount(source) == 2)
		let properties = try #require(CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
		let gif = try #require(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
		#expect((gif[kCGImagePropertyGIFLoopCount] as? NSNumber)?.intValue == inputPlayCount)
		for index in 0 ..< 2 {
			let frame = try #require(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])
			let timing = try #require(frame[kCGImagePropertyGIFDictionary] as? [CFString: Any])
			#expect((timing[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?
				.doubleValue == (index == 0 ? 0.02 : 0.07))
		}
	}

	@Test("A one-frame GIF retains its animation container")
	func singleFrameGIF() async throws {
		let data = Self.gif(frames: 1)
		let preview = try await NativeInlineImageDecoder.prepare(data, limits: .init())
		#expect(preview.data == data)
	}

	@Test("APNG preserves its original animation controls")
	func animatedPNG() async throws {
		let still = try Self.stillImage(width: 8, height: 8)
		let source = try #require(CGImageSourceCreateWithData(still as CFData, nil))
		let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
		let data = NSMutableData()
		let destination = try #require(CGImageDestinationCreateWithData(
			data,
			UTType.png.identifier as CFString,
			2,
			nil
		))
		CGImageDestinationSetProperties(destination, [
			kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 4],
		] as CFDictionary)
		for delay in [0.04, 0.17] {
			CGImageDestinationAddImage(destination, image, [
				kCGImagePropertyPNGDictionary: [
					kCGImagePropertyAPNGUnclampedDelayTime: delay,
					kCGImagePropertyAPNGDelayTime: delay,
				],
			] as CFDictionary)
		}
		try #require(CGImageDestinationFinalize(destination))
		let preview = try await NativeInlineImageDecoder.prepare(data as Data, limits: .init())
		#expect(preview.data == data as Data)
		#expect(try NativeInlineImageContainer.animation(in: preview.data, limits: .init())?.frames == 2)
	}

	@Test("Enormous compressed canvases and excess frames reject before pixel decoding")
	func compressedBombs() async throws {
		var enormous = Self.gif(frames: 1)
		enormous.replaceSubrange(6 ..< 10, with: [255, 255, 255, 255])
		await #expect(throws: NativeInlineImageError.self) {
			try await NativeInlineImageDecoder.prepare(enormous, limits: .init())
		}
		await #expect(throws: NativeInlineImageError.self) {
			try await NativeInlineImageDecoder.prepare(Self.gif(frames: 121), limits: .init())
		}
		var limits = NativeInlineImageLimits()
		limits.maximumDecodedBytes = 400 // Each frame fits, but two full canvases do not.
		await #expect(throws: NativeInlineImageError.self) {
			try await NativeInlineImageDecoder.prepare(Self.gif(frames: 2), limits: limits)
		}
		let compressed = try Self.stillImage(width: 1024, height: 1024)
		#expect(compressed.count < 128 * 1024)
		limits.maximumDecodedBytes = 1024 * 1024
		await #expect(throws: NativeInlineImageError.self) {
			try await NativeInlineImageDecoder.prepare(compressed, limits: limits)
		}
	}

	@Test("Dimension, pixel, stride and reservation arithmetic rejects overflow")
	func checkedArithmetic() throws {
		var limits = NativeInlineImageLimits()
		limits.maximumDimension = Int.max
		limits.maximumPixels = Int.max
		limits.maximumDecodedBytes = Int.max
		#expect(throws: NativeInlineImageError.self) { try limits.footprint(width: Int.max, height: Int.max) }
		#expect(throws: NativeInlineImageError.self) { try limits.footprint(width: Int.max / 8, height: 1) }
		#expect(throws: NativeInlineImageError.self) { try limits.footprint(width: 0, height: 1) }
		#expect(limits.workingByteCount == nil)
		#expect(NativeInlineImageLimits.product(Int.max, 2) == nil)
		#expect(NativeInlineImageBudget().reserve(view: "overflow", bytes: limits.workingByteCount) == nil)
	}

	@Test("Malformed, truncated and non-image bodies never become previews")
	func invalidBodies() async {
		for data in [Data(), Data("<svg/>".utf8), Self.gif(frames: 2).dropLast(8)] {
			await #expect(throws: NativeInlineImageError.self) {
				try await NativeInlineImageDecoder.prepare(data, limits: .init())
			}
		}
	}

	@Test("Unknown and dishonest lengths are bounded by bytes actually streamed", arguments: [nil, "1", "65537"])
	func streamedBodyLimit(contentLength: String?) async throws {
		var headers = ["Content-Type": "image/gif"]
		headers["Content-Length"] = contentLength
		let url = InlineImageTestProtocol.register(.init(
			headers: headers,
			chunk: Data(repeating: 0, count: 16384),
			repetitions: 5
		))
		defer { InlineImageTestProtocol.remove(url) }
		var limits = NativeInlineImageLimits()
		limits.maximumEncodedBytes = 65536
		await #expect(throws: NativeInlineImageError.self) {
			try await NativeInlineImageTransfer.download(
				url,
				limits: limits,
				protocolClasses: [InlineImageTestProtocol.self]
			)
		}
	}

	@Test("HTTP response and MIME gates reject before decoding", arguments: [403, 200])
	func responseGates(status: Int) async {
		let url = InlineImageTestProtocol.register(.init(
			status: status,
			headers: ["Content-Type": "text/html"],
			chunk: Self.gif(frames: 1)
		))
		defer { InlineImageTestProtocol.remove(url) }
		await #expect(throws: NativeInlineImageError.self) {
			try await NativeInlineImageTransfer.download(
				url,
				limits: .init(),
				protocolClasses: [InlineImageTestProtocol.self]
			)
		}
	}

	@Test("A body exactly at the streaming cap is accepted without trusting its length")
	func exactStreamLimit() async throws {
		let chunk = Self.gif(frames: 2)
		let url = InlineImageTestProtocol.register(.init(chunk: chunk))
		defer { InlineImageTestProtocol.remove(url) }
		var limits = NativeInlineImageLimits()
		limits.maximumEncodedBytes = chunk.count
		let result = try await NativeInlineImageTransfer.download(
			url,
			limits: limits,
			protocolClasses: [InlineImageTestProtocol.self]
		)
		#expect(result == chunk)
	}

	@Test("A PNG transcode cannot grow past the output byte cap")
	func boundedEncodedOutput() async throws {
		let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		let context = try #require(CGContext(
			data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512,
			space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
		))
		let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
		var random: UInt32 = 1
		for index in 0 ..< 65536 {
			random = random &* 1_664_525 &+ 1_013_904_223
			pixels[index] = UInt8(truncatingIfNeeded: random >> 24)
		}
		let image = try #require(context.makeImage())
		let data = NSMutableData()
		let destination = try #require(CGImageDestinationCreateWithData(
			data,
			UTType.jpeg.identifier as CFString,
			1,
			nil
		))
		CGImageDestinationAddImage(
			destination,
			image,
			[kCGImageDestinationLossyCompressionQuality: 0.05] as CFDictionary
		)
		try #require(CGImageDestinationFinalize(destination))
		var limits = NativeInlineImageLimits()
		limits.maximumEncodedBytes = data.length
		await #expect(throws: NativeInlineImageError.self) {
			try await NativeInlineImageDecoder.prepare(data as Data, limits: limits)
		}
	}

	@Test("Non-HTTP schemes reject synchronously without network work")
	func schemeGate() throws {
		let budget = NativeInlineImageBudget()
		let loader = NativeInlineImageLoader(budget: budget, protocolClasses: [InlineImageTestProtocol.self])
		var rejected = 0
		for address in ["file:///tmp/image.png", "ftp://example.invalid/image.png", "data:image/gif;base64,AAAA"] {
			let url = try #require(URL(string: address))
			let token = loader
				.load(url: url, viewIdentifier: "view", lineNumber: "line", linkIdentifier: "link") { result in
					if case .failure = result {
						rejected += 1
					}
				}
			#expect(token == nil)
		}
		#expect(rejected == 3)
		#expect(budget.entryCount == 0)
	}

	@Test("Global and per-view limits reject explicitly instead of queuing")
	func concurrentAdmission() async throws {
		let url = InlineImageTestProtocol.register(.init(hold: true))
		defer { InlineImageTestProtocol.remove(url) }
		let budget = NativeInlineImageBudget(maximumRequests: 2, maximumViewRequests: 1)
		let first = NativeInlineImageLoader(budget: budget, protocolClasses: [InlineImageTestProtocol.self])
		let second = NativeInlineImageLoader(budget: budget, protocolClasses: [InlineImageTestProtocol.self])
		var callbacks = 0
		let completion: @MainActor (Result<TranscriptInlineImage, Error>) -> Void = { _ in callbacks += 1 }
		#expect(first.load(
			url: url,
			viewIdentifier: "one",
			lineNumber: "1",
			linkIdentifier: "a",
			completion: completion
		) != nil)
		#expect(second.load(
			url: url,
			viewIdentifier: "one",
			lineNumber: "2",
			linkIdentifier: "a",
			completion: completion
		) == nil)
		#expect(second.load(
			url: url,
			viewIdentifier: "two",
			lineNumber: "1",
			linkIdentifier: "a",
			completion: completion
		) != nil)
		#expect(first.load(
			url: url,
			viewIdentifier: "three",
			lineNumber: "1",
			linkIdentifier: "a",
			completion: completion
		) == nil)
		#expect(budget.activeCount == 2)
		#expect(callbacks == 2)
		first.cancelAll()
		second.cancelAll()
		#expect(budget.activeCount == 2) // Cancellation has not released workers' memory yet.
		try await waitUntil { budget.entryCount == 0 }
		#expect(callbacks == 2)
	}

	@Test("Retained previews consume memory and entry slots until the line is released")
	func retainedReservations() async throws {
		let url = InlineImageTestProtocol.register(.init(chunk: Self.gif(frames: 2)))
		defer { InlineImageTestProtocol.remove(url) }
		let budget = NativeInlineImageBudget(maximumEntries: 1)
		let loader = NativeInlineImageLoader(budget: budget, protocolClasses: [InlineImageTestProtocol.self])
		var result: Result<TranscriptInlineImage, Error>?
		loader.load(url: url, viewIdentifier: "view", lineNumber: "line", linkIdentifier: "link") { result = $0 }
		try await waitUntil { result != nil }
		let image = try #require(result).get()
		#expect(image.imageData == Self.gif(frames: 2))
		#expect(budget.activeCount == 0)
		#expect(budget.entryCount == 1)
		#expect(budget.reservedByteCount > image.imageData.count)
		var rejected = false
		#expect(loader.load(url: url, viewIdentifier: "view", lineNumber: "other", linkIdentifier: "link") {
			if case .failure = $0 {
				rejected = true
			}
		} == nil)
		#expect(rejected)
		loader.cancelLoads(forView: "view", lineNumber: "line")
		#expect(budget.entryCount == 0)
		#expect(budget.reservedByteCount == 0)
	}

	@Test("Byte budgets and view entry limits include retained previews")
	func budgetBounds() throws {
		let budget = NativeInlineImageBudget(
			maximumBytes: 100, maximumViewBytes: 60, maximumEntries: 3, maximumViewEntries: 1
		)
		let first = try #require(budget.reserve(view: "one", bytes: 60))
		budget.retain(first, bytes: 50)
		#expect(budget.reserve(view: "one", bytes: 1) == nil)
		#expect(budget.reserve(view: "two", bytes: 51) == nil)
		#expect(budget.reserve(view: "two", bytes: 61) == nil)
		let second = try #require(budget.reserve(view: "two", bytes: 50))
		#expect(budget.reservedByteCount == 100)
		budget.release(first)
		budget.release(first)
		budget.release(second)
		#expect(budget.reservedByteCount == 0)
	}

	@Test("A receiver can reject a completed preview and release its reservation synchronously")
	func receiverRejection() async throws {
		let url = InlineImageTestProtocol.register(.init(chunk: Self.gif(frames: 1)))
		defer { InlineImageTestProtocol.remove(url) }
		let budget = NativeInlineImageBudget()
		let loader = NativeInlineImageLoader(budget: budget, protocolClasses: [InlineImageTestProtocol.self])
		var delivered = false
		var token: UUID?
		token = loader.load(url: url, viewIdentifier: "view", lineNumber: "line", linkIdentifier: "link") { result in
			if case .success = result {
				delivered = true
			}
			if let token {
				loader.cancelLoad(token)
			}
			#expect(budget.entryCount == 0)
		}
		try await waitUntil { delivered }
		#expect(budget.reservedByteCount == 0)
	}

	@Test("Cancellation stops transport, suppresses stale delivery and cannot remove a replacement")
	func cancellationAndReplacement() async throws {
		let pending = InlineImageTestProtocol.register(.init(hold: true))
		let ready = InlineImageTestProtocol.register(.init(chunk: Self.gif(frames: 2)))
		defer {
			InlineImageTestProtocol.remove(pending)
			InlineImageTestProtocol.remove(ready)
		}
		let budget = NativeInlineImageBudget()
		let loader = NativeInlineImageLoader(budget: budget, protocolClasses: [InlineImageTestProtocol.self])
		var stale = 0
		var delivered = 0
		loader
			.load(url: pending, viewIdentifier: "view", lineNumber: "line", linkIdentifier: "link") { _ in stale += 1 }
		try await waitUntil { InlineImageTestProtocol.started(pending) }
		loader.cancelLoads(forView: "view", lineNumber: "line")
		#expect(loader.load(url: ready, viewIdentifier: "view", lineNumber: "line", linkIdentifier: "link") {
			if case .success = $0 {
				delivered += 1
			}
		} != nil)
		try await waitUntil { delivered == 1 && budget.activeCount == 0 && InlineImageTestProtocol.stopped(pending) }
		#expect(stale == 0)
		#expect(budget.entryCount == 1)
		loader.cancelAll()
		#expect(budget.entryCount == 0)
	}

	@Test("Loader destruction cancels workers without retaining the loader or delivering callbacks")
	func destruction() async throws {
		let url = InlineImageTestProtocol.register(.init(hold: true))
		defer { InlineImageTestProtocol.remove(url) }
		let budget = NativeInlineImageBudget()
		var loader: NativeInlineImageLoader? = NativeInlineImageLoader(
			budget: budget,
			protocolClasses: [InlineImageTestProtocol.self]
		)
		let isReleased = { [weak loader] in loader == nil }
		var callbacks = 0
		loader?
			.load(url: url, viewIdentifier: "view", lineNumber: "line", linkIdentifier: "link") { _ in callbacks += 1 }
		try await waitUntil { InlineImageTestProtocol.started(url) }
		loader = nil
		#expect(isReleased())
		try await waitUntil { budget.entryCount == 0 && InlineImageTestProtocol.stopped(url) }
		#expect(callbacks == 0)
	}

	@Test("Transport and decode failures release reservations before receiver reentry")
	func failureReleasesReservation() async throws {
		for fixture in [InlineImageTestProtocol.Fixture(status: 500), .init(chunk: Data("invalid".utf8))] {
			let url = InlineImageTestProtocol.register(fixture)
			defer { InlineImageTestProtocol.remove(url) }
			let budget = NativeInlineImageBudget(maximumEntries: 1)
			let loader = NativeInlineImageLoader(budget: budget, protocolClasses: [InlineImageTestProtocol.self])
			var failed = false
			loader.load(url: url, viewIdentifier: "view", lineNumber: "line", linkIdentifier: "link") {
				if case .failure = $0 {
					failed = true
				}
				#expect(budget.entryCount == 0)
			}
			try await waitUntil { failed }
			#expect(budget.reservedByteCount == 0)
		}
	}

	private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
		let deadline = ContinuousClock.now + .seconds(3)
		while !condition(), ContinuousClock.now < deadline {
			try await Task.sleep(for: .milliseconds(5))
		}
		try #require(condition())
	}

	private static func stillImage(width: Int, height: Int, orientation: Int = 1) throws -> Data {
		let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
		let context = try #require(CGContext(
			data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
			space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		))
		try context.setFillColor(#require(CGColor(colorSpace: space, components: [0.9, 0.2, 0.1, 1])))
		context.fill(CGRect(x: 0, y: 0, width: width, height: height))
		let image = try #require(context.makeImage())
		let data = NSMutableData()
		let destination = try #require(CGImageDestinationCreateWithData(
			data,
			UTType.jpeg.identifier as CFString,
			1,
			nil
		))
		CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
		try #require(CGImageDestinationFinalize(destination))
		return data as Data
	}

	private static func gif(frames: Int) -> Data {
		var data = Data("GIF89a".utf8)
		data.append(contentsOf: [1, 0, 1, 0, 0x80, 0, 0, 255, 0, 0, 0, 255, 0])
		data.append(contentsOf: [0x21, 0xFF, 11])
		data.append(Data("NETSCAPE2.0".utf8))
		data.append(contentsOf: [3, 1, 3, 0, 0])
		for index in 0 ..< frames {
			data.append(contentsOf: [0x21, 0xF9, 4, index.isMultiple(of: 2) ? 0x09 : 0x0D, index == 0 ? 2 : 7, 0, 0, 0])
			data.append(contentsOf: [
				0x2C,
				0,
				0,
				0,
				0,
				1,
				0,
				1,
				0,
				0,
				2,
				2,
				index.isMultiple(of: 2) ? 0x44 : 0x4C,
				1,
				0,
			])
		}
		data.append(0x3B)
		return data
	}
}

final nonisolated class InlineImageTestProtocol: URLProtocol { // nonisolated: immutable
	struct Fixture: Sendable {
		var status = 200
		var headers = ["Content-Type": "image/gif"]
		var chunk = Data()
		var repetitions = 1
		var hold = false
		var started = false
		var stopped = false
	}

	private static let fixtures = Mutex<[URL: Fixture]>([:])

	static func register(_ fixture: Fixture) -> URL {
		let url = URL(string: "https://inline-image.invalid/\(UUID().uuidString)")!
		fixtures.withLock { $0[url] = fixture }
		return url
	}

	static func remove(_ url: URL) {
		_ = fixtures.withLock { $0.removeValue(forKey: url) }
	}

	static func started(_ url: URL) -> Bool {
		fixtures.withLock { $0[url]?.started == true }
	}

	static func stopped(_ url: URL) -> Bool {
		fixtures.withLock { $0[url]?.stopped == true }
	}

	override static func canInit(with _: URLRequest) -> Bool {
		true
	}

	override static func canonicalRequest(for request: URLRequest) -> URLRequest {
		request
	}

	override func startLoading() {
		guard let url = request.url,
		      let fixture = Self.fixtures.withLock({ fixtures in
		      	fixtures[url]?.started = true
		      	return fixtures[url]
		      }),
		      let response = HTTPURLResponse(
		      	url: url,
		      	statusCode: fixture.status,
		      	httpVersion: "HTTP/1.1",
		      	headerFields: fixture.headers
		      )
		else {
			client?.urlProtocol(self, didFailWithError: URLError(.badURL))
			return
		}
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		if fixture.hold {
			return
		}
		for _ in 0 ..< fixture.repetitions {
			client?.urlProtocol(self, didLoad: fixture.chunk)
		}
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {
		guard let url = request.url else { return }
		Self.fixtures.withLock { $0[url]?.stopped = true }
	}
}
