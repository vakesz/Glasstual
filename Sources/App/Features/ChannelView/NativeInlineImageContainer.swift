/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// Counts animation records without letting ImageIO first build an arbitrarily
/// large frame table. Pixel decoding and full format validation remain ImageIO's.
nonisolated enum NativeInlineImageContainer { // nonisolated: value
	struct Animation {
		let frames: Int
		let decodedBytes: Int
	}

	static func animation(in data: Data, limits: NativeInlineImageLimits) throws -> Animation? {
		try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
			if bytes.starts(with: [71, 73, 70, 56]) {
				return try gifFrames(bytes, limits: limits)
			}
			if bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) {
				return try pngFrames(bytes, limits: limits)
			}
			return nil
		}
	}

	private static func gifFrames(_ bytes: UnsafeRawBufferPointer,
	                              limits: NativeInlineImageLimits) throws -> Animation
	{
		guard bytes.count >= 13 else { throw NativeInlineImageError.unsupportedContent }
		let width = Int(bytes[6]) | Int(bytes[7]) << 8
		let height = Int(bytes[8]) | Int(bytes[9]) << 8
		let footprint = try limits.footprint(width: width, height: height)
		var offset = 13
		if bytes[10] & 0x80 != 0 {
			offset += 3 * (1 << (Int(bytes[10] & 7) + 1))
		}
		var frames = 0
		while offset < bytes.count {
			try Task.checkCancellation()
			let marker = bytes[offset]
			offset += 1
			if marker == 0x3B {
				guard frames > 0 else { throw NativeInlineImageError.unsupportedContent }
				return Animation(frames: frames, decodedBytes: footprint * frames)
			}
			if marker == 0x2C {
				guard bytes.count - offset >= 9 else { throw NativeInlineImageError.unsupportedContent }
				let left = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
				let top = Int(bytes[offset + 2]) | Int(bytes[offset + 3]) << 8
				let frameWidth = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8
				let frameHeight = Int(bytes[offset + 6]) | Int(bytes[offset + 7]) << 8
				guard frameWidth > 0, frameHeight > 0, frameWidth <= width, frameHeight <= height,
				      left <= width - frameWidth, top <= height - frameHeight,
				      frames < limits.maximumFrames, frames < limits.maximumDecodedBytes / footprint
				else { throw NativeInlineImageError.resourceLimit }
				frames += 1
				let packed = bytes[offset + 8]
				offset += 9
				if packed & 0x80 != 0 {
					offset += 3 * (1 << (Int(packed & 7) + 1))
				}
				offset += 1 // LZW minimum code size, followed by bounded sub-blocks.
			} else if marker == 0x21 {
				offset += 1 // Extension label; all extensions use the sub-block envelope.
			} else {
				throw NativeInlineImageError.unsupportedContent
			}
			while true {
				guard offset < bytes.count else { throw NativeInlineImageError.unsupportedContent }
				let length = Int(bytes[offset])
				offset += 1
				guard length <= bytes.count - offset else { throw NativeInlineImageError.unsupportedContent }
				offset += length
				if length == 0 {
					break
				}
			}
		}
		throw NativeInlineImageError.unsupportedContent
	}

	private static func pngFrames(_ bytes: UnsafeRawBufferPointer,
	                              limits: NativeInlineImageLimits) throws -> Animation?
	{
		func integer(at offset: Int) -> Int {
			Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 |
				Int(bytes[offset + 3])
		}
		var offset = 8
		var declaredFrames: Int?
		var frames = 0
		var footprint = 0
		var width = 0
		var height = 0
		while bytes.count - offset >= 12 {
			try Task.checkCancellation()
			let length = integer(at: offset)
			guard length <= bytes.count - offset - 12 else { throw NativeInlineImageError.unsupportedContent }
			let type = integer(at: offset + 4)
			switch type {
			case 0x4948_4452: // IHDR
				guard offset == 8, length == 13 else { throw NativeInlineImageError.unsupportedContent }
				width = integer(at: offset + 8)
				height = integer(at: offset + 12)
				footprint = try limits.footprint(width: width, height: height)
			case 0x6163_544C: // acTL
				guard length == 8, declaredFrames == nil,
				      footprint > 0 else { throw NativeInlineImageError.unsupportedContent }
				let count = integer(at: offset + 8)
				guard count > 0, count <= limits.maximumFrames, count <= limits.maximumDecodedBytes / footprint else {
					throw NativeInlineImageError.resourceLimit
				}
				declaredFrames = count
			case 0x6663_544C: // fcTL
				guard length == 26, let declaredFrames,
				      frames < declaredFrames else { throw NativeInlineImageError.unsupportedContent }
				let frameWidth = integer(at: offset + 12)
				let frameHeight = integer(at: offset + 16)
				guard frameWidth > 0, frameHeight > 0, frameWidth <= width, frameHeight <= height,
				      integer(at: offset + 20) <= width - frameWidth,
				      integer(at: offset + 24) <= height - frameHeight,
				      bytes[offset + 32] <= 2, bytes[offset + 33] <= 1
				else { throw NativeInlineImageError.unsupportedContent }
				frames += 1
			case 0x4945_4E44: // IEND
				guard footprint > 0, length == 0, declaredFrames == nil || declaredFrames == frames else {
					throw NativeInlineImageError.unsupportedContent
				}
				return declaredFrames.map { Animation(frames: $0, decodedBytes: footprint * $0) }
			default: break
			}
			offset += length + 12
		}
		throw NativeInlineImageError.unsupportedContent
	}
}
