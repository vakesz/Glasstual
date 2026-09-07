/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct NativeInlineImageLimits: Sendable { // nonisolated: value
	var maximumEncodedBytes = 16 * 1024 * 1024
	var maximumDimension = 16384
	var maximumPixels = 16 * 1024 * 1024
	var maximumFrames = 120
	var maximumDecodedBytes = 64 * 1024 * 1024
	var thumbnailDimension = 1024

	var workingByteCount: Int? {
		guard maximumEncodedBytes > 0, maximumDimension > 0, maximumPixels > 0,
		      maximumFrames > 0, maximumDecodedBytes > 0, thumbnailDimension > 0,
		      thumbnailDimension <= maximumDimension,
		      let encoded = Self.product(maximumEncodedBytes, 3),
		      let decoded = Self.product(maximumDecodedBytes, 2)
		else { return nil }
		let total = encoded.addingReportingOverflow(decoded)
		return total.overflow ? nil : total.partialValue
	}

	static func product(_ lhs: Int, _ rhs: Int) -> Int? {
		guard lhs >= 0, rhs >= 0 else { return nil }
		let result = lhs.multipliedReportingOverflow(by: rhs)
		return result.overflow ? nil : result.partialValue
	}

	func footprint(width: Int, height: Int) throws -> Int {
		guard width > 0, height > 0, width <= maximumDimension, height <= maximumDimension,
		      let pixels = Self.product(width, height), pixels <= maximumPixels,
		      let row = Self.product(width, 16), row <= Int.max - 256,
		      let bytes = Self.product(row + 256, height), bytes <= maximumDecodedBytes
		else { throw NativeInlineImageError.resourceLimit }
		// Allow 128-bit pixels and row padding, not merely compressed size or RGBA8.
		return bytes
	}
}

nonisolated enum NativeInlineImageDecoder { // nonisolated: value
	struct Preview: Sendable {
		let data: Data
		let residentByteCount: Int
	}

	private struct Output {
		var data = Data()
		let limit: Int
		var exceeded = false
	}

	@concurrent
	static func prepare(_ data: Data, limits: NativeInlineImageLimits) async throws -> Preview {
		try Task.checkCancellation()
		guard limits.workingByteCount != nil, !data.isEmpty, data.count <= limits.maximumEncodedBytes else {
			throw NativeInlineImageError.resourceLimit
		}
		return try autoreleasepool {
			let animation = try NativeInlineImageContainer.animation(in: data, limits: limits)
			let options = [kCGImageSourceShouldCache: false] as CFDictionary
			guard let source = CGImageSourceCreateWithData(data as CFData, options),
			      CGImageSourceGetStatus(source) == .statusComplete,
			      let type = CGImageSourceGetType(source) as String?,
			      [UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier,
			       UTType.tiff.identifier, UTType.heic.identifier, UTType.heif.identifier,
			       UTType.webP.identifier].contains(type)
			else { throw NativeInlineImageError.unsupportedContent }
			let count = CGImageSourceGetCount(source)
			guard count > 0, count <= limits.maximumFrames else { throw NativeInlineImageError.resourceLimit }
			guard animation == nil || animation?.frames == count
			else { throw NativeInlineImageError.unsupportedContent }
			let animated = count > 1 || animation != nil
			guard !animated || type == UTType.gif.identifier || type == UTType.png.identifier else {
				throw NativeInlineImageError.unsupportedContent
			}
			var aggregate = 0
			var canvasWidth = 0
			var canvasHeight = 0
			if let properties = CGImageSourceCopyProperties(source, options) as? [CFString: Any] {
				canvasWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
				canvasHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
			}
			// Probe every frame before asking any codec to allocate pixel storage.
			for index in 0 ..< count {
				try Task.checkCancellation()
				guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, options) as? [CFString: Any],
				      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
				      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
				      let depth = properties[kCGImagePropertyDepth] as? NSNumber,
				      depth.intValue > 0, depth.intValue <= 16
				else { throw NativeInlineImageError.unsupportedContent }
				let footprint = try limits.footprint(
					width: max(canvasWidth, width.intValue), height: max(canvasHeight, height.intValue)
				)
				guard footprint <= limits.maximumDecodedBytes - aggregate
				else { throw NativeInlineImageError.resourceLimit }
				aggregate += footprint
			}
			if animated {
				for index in 0 ..< count {
					try Task.checkCancellation()
					try autoreleasepool {
						guard let image = CGImageSourceCreateImageAtIndex(source, index, [
							kCGImageSourceShouldCache: true,
							kCGImageSourceShouldCacheImmediately: true,
						] as CFDictionary) else { throw NativeInlineImageError.unsupportedContent }
						try validate(image, limits: limits)
					}
					CGImageSourceRemoveCacheAtIndex(source, index)
				}
				try Task.checkCancellation()
				// Byte preservation also preserves disposal, blend operations, loop counts,
				// unclamped delays and colour profiles. Never transcode to a still frame.
				return Preview(data: data, residentByteCount: data.count + max(aggregate, animation?.decodedBytes ?? 0))
			}
			guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
				kCGImageSourceCreateThumbnailFromImageAlways: true,
				kCGImageSourceCreateThumbnailWithTransform: true,
				kCGImageSourceThumbnailMaxPixelSize: limits.thumbnailDimension,
				kCGImageSourceShouldCacheImmediately: true,
			] as CFDictionary) else { throw NativeInlineImageError.unsupportedContent }
			try validate(image, limits: limits)
			try Task.checkCancellation()
			let output = try encode(image, maximumBytes: limits.maximumEncodedBytes)
			try Task.checkCancellation()
			let footprint = try limits.footprint(width: image.width, height: image.height)
			return Preview(data: output, residentByteCount: output.count + footprint)
		}
	}

	private static func encode(_ image: CGImage, maximumBytes: Int) throws -> Data {
		var output = Output(limit: maximumBytes)
		// ImageIO writes synchronously through this consumer. The pointer never
		// escapes this scope and its value is confined to the decoding executor.
		try withUnsafeMutablePointer(to: &output) { pointer in
			var callbacks = CGDataConsumerCallbacks(putBytes: { info, bytes, count in
				guard let info else { return 0 }
				let output = info.assumingMemoryBound(to: Output.self)
				guard !output.pointee.exceeded, count <= output.pointee.limit - output.pointee.data.count else {
					output.pointee.exceeded = true
					return 0
				}
				output.pointee.data.append(bytes.assumingMemoryBound(to: UInt8.self), count: count)
				return count
			}, releaseConsumer: nil)
			guard let consumer = CGDataConsumer(info: pointer, cbks: &callbacks),
			      let destination = CGImageDestinationCreateWithDataConsumer(
			      	consumer,
			      	UTType.png.identifier as CFString,
			      	1,
			      	nil
			      )
			else { throw NativeInlineImageError.unsupportedContent }
			// The transform bakes EXIF orientation into pixels. ImageIO embeds the
			// resulting CGImage colour space instead of dropping its profile.
			CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
			guard CGImageDestinationFinalize(destination), !pointer.pointee.exceeded else {
				throw NativeInlineImageError.resourceLimit
			}
		}
		return output.data
	}

	private static func validate(_ image: CGImage, limits: NativeInlineImageLimits) throws {
		_ = try limits.footprint(width: image.width, height: image.height)
		guard let bytes = NativeInlineImageLimits.product(image.bytesPerRow, image.height),
		      bytes <= limits.maximumDecodedBytes, image.bitsPerPixel <= 128
		else { throw NativeInlineImageError.resourceLimit }
	}
}
