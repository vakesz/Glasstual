/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2012 - 2020 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Darwin
import GlasstualPluginKit
import Metal

@MainActor
enum SystemProfileReport {
	static func applicationActiveStyle(metrics: PluginApplicationMetrics, host: PluginHostContext) -> String {
		guard let snapshot = host.themeSnapshot else {
			return ""
		}

		let storage = switch snapshot.storageLocation {
		case .bundled:
			String(localized: .BasicLanguage.bundledTheme)
		case .custom:
			String(localized: .BasicLanguage.customTheme)
		case .unknown:
			""
		}
		let sidebar = SystemProfileInformation.sidebarAppearance(usesDarkAppearance: metrics.usesDarkSidebar)
		let theme = SystemProfileInformation.themeAppearance(host: host)
		let appearance = sidebar == theme
			? SystemProfilerLocalization.string(.BasicLanguage.appearance(sidebar))
			: SystemProfilerLocalization.string(.BasicLanguage.separateAppearances(theme, sidebar))
		return SystemProfilerLocalization.string(.BasicLanguage.currentStyle(snapshot.name, storage, appearance))
	}

	static func applicationAndSystemUptime(host: PluginHostContext) -> String {
		let units: NSCalendar.Unit = [.day, .hour, .minute, .second]
		let system = PluginHost.humanReadableTimeInterval(
			ProcessInfo.processInfo.systemUptime,
			shortValue: false,
			units: units
		)
		let application = PluginHost.humanReadableTimeInterval(
			host.applicationSnapshot?.timeIntervalSinceLaunch ?? 0,
			shortValue: false,
			units: units
		)
		return SystemProfilerLocalization.string(.BasicLanguage.uptimes(system, application))
	}

	static func applicationBandwidthStatistics(metrics: PluginApplicationMetrics) -> String {
		SystemProfilerLocalization.string(
			.BasicLanguage.applicationBandwidthStatistics(
				PluginHost.formattedNumber(Int(metrics.messagesSent)),
				PluginHost.formattedNumber(Int(metrics.messagesReceived)),
				PluginHost.humanReadableTimeInterval(metrics.lastMessageReceived, shortValue: true, units: .second),
				SystemProfileInformation.formattedByteCount(metrics.bandwidthIn),
				SystemProfileInformation.formattedByteCount(metrics.bandwidthOut)
			)
		)
	}

	static func applicationMemoryUsage(metrics: PluginApplicationMetrics) -> String {
		SystemProfilerLocalization.string(
			.BasicLanguage.applicationMemoryUsage(
				SystemProfileInformation.formattedByteCount(SystemProfileInformation.applicationMemoryUsage()),
				PluginHost.formattedNumber(metrics.visibleLineCount)
			)
		)
	}

	static func applicationRuntimeStatistics(host: PluginHostContext) -> String {
		guard let snapshot = host.applicationSnapshot else {
			return ""
		}

		let birthday = Date().timeIntervalSince(Date(timeIntervalSince1970: snapshot.birthday))
		let runtime = min(snapshot.timeIntervalSinceInstall, birthday)
		return SystemProfilerLocalization.string(
			.BasicLanguage.applicationRuntimeStatistics(
				PluginHost.formattedNumber(Int(clamping: snapshot.runCount)),
				PluginHost.humanReadableTimeInterval(runtime, shortValue: false)
			)
		)
	}

	/// Formats what ``SystemProfileInformation/mountedVolumeCapacities()``
	/// collected. The collection is the slow half and does not run here: it
	/// mounts nothing, but it stats every mounted volume, and a network share
	/// or a sleeping disk answers when it answers.
	static func systemDiskSpaceInformation(volumes: [SystemProfileInformation.VolumeCapacity]) -> String {
		let descriptions = volumes.enumerated().map { index, volume -> String in
			let totalDescription = SystemProfileInformation.formattedByteCount(volume.totalCapacity)
			let freeDescription = SystemProfileInformation.formattedByteCount(volume.availableCapacity)
			let name = volume.name
			return if index == 0 {
				SystemProfilerLocalization.string(.BasicLanguage.firstMountedDrive(
					name,
					totalDescription,
					freeDescription
				))
			} else {
				SystemProfilerLocalization.string(
					.BasicLanguage.additionalMountedDrive(name, totalDescription, freeDescription)
				)
			}
		}
		guard descriptions.isEmpty == false else {
			return SystemProfilerLocalization.string(.BasicLanguage.mountedDrivesUnavailable)
		}
		return SystemProfilerLocalization.string(.BasicLanguage.mountedDrivesHeading(descriptions.joined()))
	}

	static func systemDisplayInformation() -> String {
		NSScreen.screens.enumerated().map { index, screen in
			let refreshRate = SystemProfileInformation.refreshRate(for: screen)
			let number = UInt(index + 1)
			return switch (index == 0, refreshRate) {
			case (true, nil):
				SystemProfilerLocalization.string(.BasicLanguage.firstDisplay(
					number,
					screen.textualScreenResolutionString
				))
			case (true, let refreshRate?):
				SystemProfilerLocalization.string(
					.BasicLanguage.firstDisplayWithRefreshRate(
						number,
						screen.textualScreenResolutionString,
						refreshRate
					)
				)
			case (false, nil):
				SystemProfilerLocalization.string(
					.BasicLanguage.additionalDisplay(number, screen.textualScreenResolutionString)
				)
			case (false, let refreshRate?):
				SystemProfilerLocalization.string(
					.BasicLanguage.additionalDisplayWithRefreshRate(
						number,
						screen.textualScreenResolutionString,
						refreshRate
					)
				)
			}
		}.joined()
	}

	/// Formats the facts ``SystemProfileInformation/hardwareFacts()`` collected.
	/// Only the screen is read here, because only the screen has to be.
	static func systemInformation(defaults: UserDefaults, facts: SystemProfileInformation.HardwareFacts) -> String {
		func enabled(_ feature: SystemProfilerFeature) -> Bool {
			defaults.bool(forKey: feature.disabledPreference.name) == false
		}

		var result = SystemProfilerLocalization.string(.BasicLanguage.systemInformationHeading)
		if let model = facts.modelName {
			result += SystemProfilerLocalization.string(.BasicLanguage.modelSegment(model))
		}
		if enabled(.cpuModel), let processor = facts.processor {
			result += SystemProfilerLocalization.string(
				.BasicLanguage.cpuCoreSegment(processor, UInt(facts.physicalCoreCount))
			)
		}
		if enabled(.memoryInformation) {
			result += SystemProfilerLocalization.string(
				.BasicLanguage.memorySegment(SystemProfileInformation.formattedByteCount(facts.physicalMemory))
			)
		}
		if enabled(.systemUptime) {
			let uptime = PluginHost.humanReadableTimeInterval(facts.systemUptime, shortValue: true)
			result += SystemProfilerLocalization.string(.BasicLanguage.uptimeSegment(uptime))
		}
		if enabled(.diskInformation), let disk = facts.rootVolumeCapacity {
			result += SystemProfilerLocalization.string(
				.BasicLanguage.spaceSegment(SystemProfileInformation.formattedByteCount(disk))
			)
		}
		if enabled(.gpuModel), let graphics = facts.graphicsDescription {
			result += SystemProfilerLocalization.string(.BasicLanguage.graphicsSegment(graphics))
		}
		if enabled(.screenResolution), let screen = NSScreen.main ?? NSScreen.screens.first {
			if let refreshRate = SystemProfileInformation.refreshRate(for: screen) {
				result += SystemProfilerLocalization.string(
					.BasicLanguage.displayWithRefreshRateSegment(
						screen.textualScreenResolutionString,
						refreshRate
					)
				)
			} else {
				result += SystemProfilerLocalization.string(
					.BasicLanguage.displaySegment(screen.textualScreenResolutionString)
				)
			}
		}
		if enabled(.operatingSystemVersion) {
			result += SystemProfilerLocalization.string(
				.BasicLanguage.operatingSystemSegment(
					SystemInformation.systemOperatingSystemName,
					SystemInformation.systemStandardVersion,
					SystemInformation.systemBuildVersion ?? ""
				)
			)
		}
		if result.hasSuffix(" \u{0002}•\u{0002}") {
			result.removeLast(4)
		}
		return result
	}

	static func systemMemoryInformation() -> String {
		let total = ProcessInfo.processInfo.physicalMemory
		let free = min(SystemProfileInformation.freeMemory(), total)
		let used = total - free
		let usedSegments = total == 0 ? 0 : min(10, Int(Double(used) / Double(total) * 10))
		let meter = "\u{0003}04" + String(repeating: "❙", count: usedSegments + 1)
			+ "\u{0003}|\u{0003}03" + String(repeating: "❙", count: 11 - usedSegments) + "\u{0003}"
		return SystemProfilerLocalization.string(
			.BasicLanguage.systemMemory(
				SystemProfileInformation.formattedByteCount(free),
				SystemProfileInformation.formattedByteCount(used),
				SystemProfileInformation.formattedByteCount(total),
				meter
			)
		)
	}

	static func systemNetworkInformation() -> String {
		let interfaces = SystemProfileInformation.networkStatistics()
		guard interfaces.isEmpty == false else {
			return SystemProfilerLocalization.string(.BasicLanguage.networkStatisticsUnavailable)
		}
		let text = interfaces.enumerated().map { index, item in
			let received = SystemProfileInformation.formattedByteCount(item.received)
			let sent = SystemProfileInformation.formattedByteCount(item.sent)
			return if index == 0 {
				SystemProfilerLocalization.string(.BasicLanguage.firstNetworkInterface(item.name, received, sent))
			} else {
				SystemProfilerLocalization.string(.BasicLanguage.additionalNetworkInterface(item.name, received, sent))
			}
		}.joined()
		return SystemProfilerLocalization.string(.BasicLanguage.networkTrafficHeading(text))
	}
}

nonisolated enum SystemProfileInformation { // nonisolated: value
	/// One mounted volume, as `/diskspace` reports it. A value, so the
	/// enumeration that produces it can run off the main actor.
	struct VolumeCapacity: Sendable {
		let name: String
		let totalCapacity: UInt64
		let availableCapacity: UInt64
	}

	/// What `/sysinfo` reports that is not the screen. A value, for the same
	/// reason: `MTLCopyAllDevices()` alone can take a wake-up's worth of time.
	struct HardwareFacts: Sendable {
		var modelName: String?
		var processor: String?
		var physicalCoreCount: UInt64 = 0
		var physicalMemory: UInt64 = 0
		var systemUptime: TimeInterval = 0
		var rootVolumeCapacity: UInt64?
		var graphicsDescription: String?
	}

	struct NetworkStatistics {
		let name: String
		let received: UInt64
		let sent: UInt64
	}

	static func formattedByteCount(_ count: UInt64) -> String {
		ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .file)
	}

	static func modelIdentifier() -> String? {
		sysctlString("hw.model")
	}

	static func processor() -> String? {
		sysctlString("machdep.cpu.brand_string")
	}

	static func physicalCoreCount() -> UInt64 {
		sysctlInteger("hw.physicalcpu")
	}

	/** Every mounted volume's capacity.

	 `@concurrent`, because this is I/O: `mountedVolumeURLs` enumerates the
	 mount table and each `resourceValues` call stats a filesystem that may be a
	 network share, a disk image or a sleeping external disk. Running it on the
	 main actor stalled the whole window for as long as the slowest mount took
	 to answer. */
	@concurrent
	static func mountedVolumeCapacities() async -> [VolumeCapacity] {
		let keys: Set<URLResourceKey> = [
			.volumeNameKey,
			.volumeTotalCapacityKey,
			.volumeAvailableCapacityForImportantUsageKey,
		]
		let volumes = FileManager.default.mountedVolumeURLs(
			includingResourceValuesForKeys: Array(keys),
			options: .skipHiddenVolumes
		) ?? []

		return volumes.compactMap { volume -> VolumeCapacity? in
			guard let values = try? volume.resourceValues(forKeys: keys),
			      let name = values.volumeName,
			      let total = values.volumeTotalCapacity,
			      let free = values.volumeAvailableCapacityForImportantUsage
			else { return nil }

			/* A mounted volume can be a network share, a disk image or a FUSE
			 mount, and its capacities are whatever that filesystem reports;
			 `volumeAvailableCapacityForImportantUsage` also goes negative when
			 purgeable-space accounting overshoots. Neither is a byte count. */
			return VolumeCapacity(
				name: name,
				totalCapacity: UInt64(clamping: total),
				availableCapacity: UInt64(clamping: free)
			)
		}
	}

	/// The hardware half of `/sysinfo`. `@concurrent` for the same reason:
	/// `MTLCopyAllDevices()` can wake a discrete GPU, and the root volume is
	/// still a filesystem that has to answer.
	@concurrent
	static func hardwareFacts() async -> HardwareFacts {
		var facts = HardwareFacts()
		if let identifier = modelIdentifier(), identifier.isEmpty == false {
			facts.modelName = modelName(for: identifier)
		}
		facts.processor = processor()
		facts.physicalCoreCount = physicalCoreCount()
		facts.physicalMemory = ProcessInfo.processInfo.physicalMemory
		facts.systemUptime = ProcessInfo.processInfo.systemUptime
		facts.rootVolumeCapacity = rootVolumeCapacity()
		facts.graphicsDescription = graphicsDescription()
		return facts
	}

	/** The shipped identifier-to-marketing-name table.

	 Decoded once. `/sysinfo` used to decode all four hundred-odd entries on
	 every invocation to read a single key out of them. */
	private static let macintoshModels: [String: String] = {
		guard let url = Bundle(for: SystemProfilerPlugin.self).url(
			forResource: "MacintoshModels",
			withExtension: "plist"
		),
			let data = try? Data(contentsOf: url),
			let models = try? PropertyListDecoder().decode([String: String].self, from: data)
		else { return [:] }
		return models
	}()

	static func modelName(for identifier: String) -> String {
		/* A virtual machine reports a model identifier with a build suffix, so
		 the table is keyed on the hypervisor's name alone. */
		let lookupKey = if identifier.hasPrefix("VMware") {
			"VMware"
		} else if identifier.hasPrefix("Parallels") {
			"Parallels"
		} else {
			identifier
		}
		return macintoshModels[lookupKey] ?? identifier
	}

	static func rootVolumeCapacity() -> UInt64? {
		let values = try? URL(fileURLWithPath: "/", isDirectory: true)
			.resourceValues(forKeys: [.volumeTotalCapacityKey])
		return values?.volumeTotalCapacity.map { UInt64(clamping: $0) }
	}

	static func graphicsDescription() -> String? {
		let names = Array(Set(MTLCopyAllDevices().map(\.name))).sorted()
		guard names.isEmpty == false else { return nil }
		return names.enumerated().map { index, name in
			index == 0
				? SystemProfilerLocalization.string(.BasicLanguage.firstListItem(name))
				: SystemProfilerLocalization.string(.BasicLanguage.additionalListItem(name))
		}.joined()
	}

	@MainActor static func sidebarAppearance(usesDarkAppearance: Bool) -> String {
		SystemProfilerLocalization.string(
			usesDarkAppearance ? .BasicLanguage.darkAppearance : .BasicLanguage.lightAppearance
		)
	}

	@MainActor static func themeAppearance(host: PluginHostContext) -> String {
		let appearance = host.themeSnapshot?.resolvedAppearance
		return SystemProfilerLocalization.string(
			appearance == .dark ? .BasicLanguage.darkAppearance : .BasicLanguage.lightAppearance
		)
	}

	static func refreshRate(for screen: NSScreen) -> String? {
		let rate = screen.textualScreenRefreshRate
		guard rate <= 58.5 || rate >= 61.5 else { return nil }
		return SystemProfilerLocalization.string(.BasicLanguage.screenRefreshRate(Float(rate)))
	}

	static func applicationMemoryUsage() -> UInt64 {
		memoryUsage(for: pid_t(ProcessInfo.processInfo.processIdentifier))
	}

	static func memoryUsage(for processIdentifier: pid_t) -> UInt64 {
		guard processIdentifier != 0 else { return 0 }
		var region = proc_regioninfo()
		var address: UInt64 = 0
		var usage: UInt64 = 0
		while proc_pidinfo(
			processIdentifier,
			PROC_PIDREGIONINFO,
			address,
			&region,
			Int32(MemoryLayout<proc_regioninfo>.size)
		) >
			0
		{
			/* The kernel's own numbers, but they still come from outside this
			 process: an overflowing pair would trap here rather than end the
			 walk. A zero-sized region would leave the address unchanged
			 forever, so that ends it too. */
			let (nextAddress, overflowed) = region.pri_address.addingReportingOverflow(region.pri_size)
			guard overflowed == false, nextAddress > address else { break }
			address = nextAddress
			if region.pri_share_mode == SM_PRIVATE {
				usage += UInt64(region.pri_private_pages_resident) * UInt64(getpagesize())
			}
		}
		return usage
	}

	static func freeMemory() -> UInt64 {
		/* mach_host_self() returns a send right that the caller owns. */
		let host = mach_host_self()
		defer { mach_port_deallocate(mach_task_self_, host) }

		var pageSize: vm_size_t = 0
		guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return 0 }
		var statistics = vm_statistics64()
		var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
		let status = withUnsafeMutablePointer(to: &statistics) { pointer in
			pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
				host_statistics64(host, HOST_VM_INFO64, rebound, &count)
			}
		}
		guard status == KERN_SUCCESS else { return 0 }
		let internalPages = max(0, Int64(statistics.internal_page_count) - Int64(statistics.purgeable_count))
		let usedPages = UInt64(internalPages) + UInt64(statistics.wire_count) + UInt64(statistics.compressor_page_count)
		let used = usedPages * UInt64(pageSize)
		return ProcessInfo.processInfo.physicalMemory > used ? ProcessInfo.processInfo.physicalMemory - used : 0
	}

	/** Per-interface byte counters.

	 Read through `NET_RT_IFLIST2`, whose `if_msghdr2` carries an `if_data64`.
	 `getifaddrs` reports the 32-bit `if_data` instead, and those counters wrap
	 every four gigabytes — a figure a single session passes — after which
	 `/netstats` reported whatever was left over rather than what had moved. */
	/// `u_short ifm_msglen`, `u_char ifm_version`, `u_char ifm_type`: the header
	/// every routing-socket message begins with, whatever kind it is.
	private static let routeMessageHeaderLength = 4

	static func networkStatistics() -> [NetworkStatistics] {
		var name: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
		var size = 0
		guard sysctl(&name, UInt32(name.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }

		var buffer = [UInt8](repeating: 0, count: size)
		guard sysctl(&name, UInt32(name.count), &buffer, &size, nil, 0) == 0 else { return [] }

		return buffer.withUnsafeBytes { raw -> [NetworkStatistics] in
			var result: [NetworkStatistics] = []
			var offset = 0

			/* Every message in the list starts with the same four bytes —
			 length, version, type — whatever kind it is, and the kernel mixes
			 several kinds in. Requiring a whole `if_msghdr`, the largest of the
			 fixed headers at 112 bytes, before looking at any of them ended the
			 walk on the short messages rather than stepping over them. */
			while offset + routeMessageHeaderLength <= size {
				let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
				let type = raw.loadUnaligned(fromByteOffset: offset + 3, as: UInt8.self)
				guard length > 0, offset + length <= size else { break }
				defer { offset += length }

				guard Int32(type) == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size else { continue }
				let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
				guard message.ifm_flags & (IFF_UP | IFF_RUNNING) != 0 else { continue }

				var interfaceName = [CChar](repeating: 0, count: Int(IFNAMSIZ))
				guard if_indextoname(UInt32(message.ifm_index), &interfaceName) != nil else { continue }
				let nameBytes = interfaceName.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
				guard let interface = String(bytes: nameBytes, encoding: .utf8),
				      interface.hasPrefix("lo") == false
				else { continue }

				let data = message.ifm_data
				guard data.ifi_ibytes >= 20_000_000, data.ifi_obytes >= 2_000_000 else { continue }
				result.append(.init(name: interface, received: data.ifi_ibytes, sent: data.ifi_obytes))
			}

			return result
		}
	}

	private static func sysctlString(_ name: String) -> String? {
		var size = 0
		guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
		var buffer = [CChar](repeating: 0, count: size)
		guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
		let bytes = buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
		return String(bytes: bytes, encoding: .utf8)
	}

	private static func sysctlInteger(_ name: String) -> UInt64 {
		var value: UInt64 = 0
		var size = MemoryLayout.size(ofValue: value)
		return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : 0
	}
}

nonisolated enum SystemProfilerLocalization { // nonisolated: value
	static func string(_ resource: LocalizedStringResource) -> String {
		String(localized: resource)
	}
}
