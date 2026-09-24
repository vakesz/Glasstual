// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("DCC display progress sampling")
struct DCCProgressSamplerTests {
	@Test("A block burst publishes the latest count at most once per interval and flushes the rest")
	func samplesBurstAndFlushesLatest() {
		var sampler = DCCProgressSampler(minimumInterval: .milliseconds(100))
		let start = ContinuousClock.now

		#expect(sampler.record(65536, at: start) == 65536)
		#expect(sampler.record(131_072, at: start.advanced(by: .milliseconds(10))) == nil)
		#expect(sampler.record(196_608, at: start.advanced(by: .milliseconds(50))) == nil)
		#expect(sampler.record(262_144, at: start.advanced(by: .milliseconds(100))) == 262_144)
		#expect(sampler.record(327_680, at: start.advanced(by: .milliseconds(105))) == nil)
		#expect(sampler.flush() == 327_680)
		#expect(sampler.flush() == nil)
	}

	@Test("A sender at its byte rate cap publishes at most eleven updates per second")
	func capsDisplayUpdatesAtSenderRateLimit() {
		var sampler = DCCProgressSampler(minimumInterval: DCCTransfer.progressInterval)
		let start = ContinuousClock.now
		var emitted: [UInt64] = []
		for block in 1 ... 160 {
			let time = start.advanced(by: .microseconds((block - 1) * 6250))
			if let bytes = sampler.record(UInt64(block * 65536), at: time) {
				emitted.append(bytes)
			}
		}
		if let bytes = sampler.flush() {
			emitted.append(bytes)
		}

		#expect(emitted.count <= 11)
		#expect(emitted.last == DCCTransfer.rateLimitBytesPerSecond)
	}

	@Test("Repeated byte counts do not make progress go backward or emit twice")
	func ignoresRepeatedCounts() {
		var sampler = DCCProgressSampler(minimumInterval: .milliseconds(100))
		let start = ContinuousClock.now

		#expect(sampler.record(100, at: start) == 100)
		#expect(sampler.record(200, at: start.advanced(by: .milliseconds(10))) == nil)
		#expect(sampler.record(150, at: start.advanced(by: .milliseconds(20))) == nil)
		#expect(sampler.flush() == 200)
		#expect(sampler.record(200, at: start.advanced(by: .milliseconds(200))) == nil)
		#expect(sampler.record(90, at: start.advanced(by: .milliseconds(300))) == nil)
		#expect(sampler.flush() == nil)
	}
}
