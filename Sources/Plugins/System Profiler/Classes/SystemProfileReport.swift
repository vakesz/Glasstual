/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import Metal

@MainActor
enum SystemProfileReport {
	private static var masterController: TXMasterController {
		NSObject.masterController()
	}

	private static var world: IRCWorld {
		masterController.world
	}

	static func applicationActiveStyle() -> String {
		let controller = TXSharedApplication.sharedThemeController()
		let storage = TPCThemeController.description(for: controller.storageLocation) ?? ""
		let sidebar = SystemProfileInformation.sidebarAppearance()
		let theme = SystemProfileInformation.themeAppearance()
		let appearance = sidebar == theme
			? SystemProfilerLocalization.string("614-dj", sidebar)
			: SystemProfilerLocalization.string("843-z4", theme, sidebar)
		return SystemProfilerLocalization.string("z37-85", controller.name, storage, appearance)
	}

	static func applicationAndSystemUptime() -> String {
		let units: NSCalendar.Unit = [.day, .hour, .minute, .second]
		let system = TXHumanReadableTimeInterval(ProcessInfo.processInfo.systemUptime, false, units) ?? ""
		let application = TXHumanReadableTimeInterval(
			TPCApplicationInfo.timeIntervalSinceApplicationLaunch(),
			false,
			units
		) ?? ""
		return SystemProfilerLocalization.string("v03-jx", system, application)
	}

	static func applicationBandwidthStatistics() -> String {
		let lastMessage = masterController.mainWindow.selectedClient.map {
			Date.timeIntervalSinceReferenceDate - $0.lastMessageReceived
		} ?? 0
		return SystemProfilerLocalization.string(
			"rua-9r",
			TXFormattedNumber(Int(world.messagesSent)),
			TXFormattedNumber(Int(world.messagesReceived)),
			TXHumanReadableTimeInterval(lastMessage, true, .second) ?? "",
			SystemProfileInformation.formattedByteCount(world.bandwidthIn),
			SystemProfileInformation.formattedByteCount(world.bandwidthOut)
		)
	}

	static func applicationMemoryUsage() -> String {
		let lines = world.clientList.reduce(0) { total, client in
			total + Int(client.viewController.numberOfLines)
				+ client.channelList.reduce(0) { $0 + Int($1.viewController.numberOfLines) }
		}
		return SystemProfilerLocalization.string(
			"scn-br",
			SystemProfileInformation.formattedByteCount(SystemProfileInformation.applicationMemoryUsage()),
			TXFormattedNumber(lines)
		)
	}

	static func applicationRuntimeStatistics() -> String {
		let birthday = Date().timeIntervalSince(Date(timeIntervalSince1970: TPCApplicationInfo.applicationBirthday()))
		let runtime = min(TPCApplicationInfo.timeIntervalSinceApplicationInstall(), birthday)
		return SystemProfilerLocalization.string(
			"6fn-xh",
			TXFormattedNumber(Int(TPCApplicationInfo.applicationRunCount())),
			TXHumanReadableTimeInterval(runtime, false, []) ?? ""
		)
	}

	static func systemDiskSpaceInformation() -> String {
		let keys: Set<URLResourceKey> = [
			.volumeNameKey,
			.volumeTotalCapacityKey,
			.volumeAvailableCapacityForImportantUsageKey,
		]
		let volumes = FileManager.default.mountedVolumeURLs(
			includingResourceValuesForKeys: Array(keys),
			options: .skipHiddenVolumes
		) ?? []
		let descriptions = volumes.enumerated().compactMap { index, volume -> String? in
			guard let values = try? volume.resourceValues(forKeys: keys),
			      let name = values.volumeName,
			      let total = values.volumeTotalCapacity,
			      let free = values.volumeAvailableCapacityForImportantUsage
			else { return nil }
			return SystemProfilerLocalization.string(
				index == 0 ? "bvr-wz" : "lct-7h",
				name,
				SystemProfileInformation.formattedByteCount(UInt64(total)),
				SystemProfileInformation.formattedByteCount(UInt64(free))
			)
		}
		guard descriptions.isEmpty == false else { return SystemProfilerLocalization.string("ler-a5") }
		return SystemProfilerLocalization.string("n6i-xd", descriptions.joined())
	}

	static func systemDisplayInformation() -> String {
		NSScreen.screens.enumerated().map { index, screen in
			let refreshRate = SystemProfileInformation.refreshRate(for: screen)
			let key = switch (index == 0, refreshRate == nil) {
			case (true, true): "441-8c"
			case (true, false): "vvt-zq"
			case (false, true): "dd1-rp"
			case (false, false): "fys-ft"
			}
			return SystemProfilerLocalization.string(
				key,
				UInt(index + 1),
				screen.screenResolutionString,
				refreshRate ?? ""
			)
		}.joined()
	}

	static func systemInformation() -> String {
		let defaults = TPCPreferencesUserDefaults.shared()
		func enabled(_ feature: String) -> Bool {
			defaults.bool(forKey: "System Profiler Extension -> Feature Disabled -> \(feature)") == false
		}

		var result = SystemProfilerLocalization.string("lxj-ha")
		if let identifier = SystemProfileInformation.modelIdentifier(), identifier.isEmpty == false {
			result += SystemProfilerLocalization.string("7g5-pf", SystemProfileInformation.modelName(for: identifier))
		}
		if enabled("CPU Model"), let processor = SystemProfileInformation.processor() {
			result += SystemProfilerLocalization.string(
				"ifk-s5",
				processor,
				UInt(SystemProfileInformation.physicalCoreCount())
			)
		}
		if enabled("Memory Information") {
			result += SystemProfilerLocalization.string(
				"1am-io",
				SystemProfileInformation.formattedByteCount(ProcessInfo.processInfo.physicalMemory)
			)
		}
		if enabled("System Uptime") {
			let uptime = TXHumanReadableTimeInterval(ProcessInfo.processInfo.systemUptime, true, []) ?? ""
			result += SystemProfilerLocalization.string("xb6-bh", uptime)
		}
		if enabled("Disk Information"), let disk = SystemProfileInformation.rootVolumeCapacity() {
			result += SystemProfilerLocalization.string("yrc-6l", SystemProfileInformation.formattedByteCount(disk))
		}
		if enabled("GPU Model"), let graphics = SystemProfileInformation.graphicsDescription() {
			result += SystemProfilerLocalization.string("q5v-uq", graphics)
		}
		if enabled("Screen Resolution"), let screen = NSScreen.main ?? NSScreen.screens.first {
			if let refreshRate = SystemProfileInformation.refreshRate(for: screen) {
				result += SystemProfilerLocalization.string("b7c-qd", screen.screenResolutionString, refreshRate)
			} else {
				result += SystemProfilerLocalization.string("22o-rg", screen.screenResolutionString)
			}
		}
		if enabled("OS Version") {
			result += SystemProfilerLocalization.string(
				"g41-p7",
				XRSystemInformation.systemOperatingSystemName ?? "macOS",
				XRSystemInformation.systemStandardVersion ?? "",
				XRSystemInformation.systemBuildVersion ?? ""
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
			"cfs-b1",
			SystemProfileInformation.formattedByteCount(free),
			SystemProfileInformation.formattedByteCount(used),
			SystemProfileInformation.formattedByteCount(total),
			meter
		)
	}

	static func systemNetworkInformation() -> String {
		let interfaces = SystemProfileInformation.networkStatistics()
		guard interfaces.isEmpty == false else { return SystemProfilerLocalization.string("li1-vn") }
		let text = interfaces.enumerated().map { index, item in
			SystemProfilerLocalization.string(
				index == 0 ? "ca4-25" : "mjo-o0",
				item.name,
				SystemProfileInformation.formattedByteCount(item.received),
				SystemProfileInformation.formattedByteCount(item.sent)
			)
		}.joined()
		return SystemProfilerLocalization.string("9f8-ej", text)
	}
}

enum SystemProfileInformation {
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

	static func modelName(for identifier: String) -> String {
		let lookupKey = identifier.hasPrefix("VMware") ? "VMware" : identifier
			.hasPrefix("Parallels") ? "Parallels" : identifier
		guard let url = Bundle(for: SystemProfilerPlugin.self).url(
			forResource: "MacintoshModels",
			withExtension: "plist"
		),
			let data = try? Data(contentsOf: url),
			let models = try? PropertyListDecoder().decode([String: String].self, from: data)
		else { return identifier }
		return models[lookupKey] ?? identifier
	}

	static func rootVolumeCapacity() -> UInt64? {
		let values = try? URL(fileURLWithPath: "/", isDirectory: true)
			.resourceValues(forKeys: [.volumeTotalCapacityKey])
		return values?.volumeTotalCapacity.map(UInt64.init)
	}

	static func graphicsDescription() -> String? {
		let names = Array(Set(MTLCopyAllDevices().map(\.name))).sorted()
		guard names.isEmpty == false else { return nil }
		return names.enumerated().map { index, name in
			SystemProfilerLocalization.string(index == 0 ? "8nu-89" : "cmk-ws", name)
		}.joined()
	}

	@MainActor static func sidebarAppearance() -> String {
		SystemProfilerLocalization
			.string(NSObject.masterController().mainWindow.isUsingDarkAppearance ? "243-yt" : "890-au")
	}

	@MainActor static func themeAppearance() -> String {
		var appearance = TXSharedApplication.sharedThemeController().theme.appearance
		if appearance == .default {
			appearance = TXSharedApplication.sharedAppearance().properties.isDarkAppearance ? .dark : .light
		}
		return SystemProfilerLocalization.string(appearance == .dark ? "243-yt" : "890-au")
	}

	static func refreshRate(for screen: NSScreen) -> String? {
		let rate = screen.screenRefreshRate
		guard rate <= 58.5 || rate >= 61.5 else { return nil }
		return SystemProfilerLocalization.string("zpt-sx", rate)
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
			address = region.pri_address + region.pri_size
			if region.pri_share_mode == SM_PRIVATE {
				usage += UInt64(region.pri_private_pages_resident) * UInt64(getpagesize())
			}
		}
		return usage
	}

	static func freeMemory() -> UInt64 {
		var pageSize: vm_size_t = 0
		guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return 0 }
		var statistics = vm_statistics64()
		var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
		let status = withUnsafeMutablePointer(to: &statistics) { pointer in
			pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
				host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
			}
		}
		guard status == KERN_SUCCESS else { return 0 }
		let internalPages = max(0, Int64(statistics.internal_page_count) - Int64(statistics.purgeable_count))
		let usedPages = UInt64(internalPages) + UInt64(statistics.wire_count) + UInt64(statistics.compressor_page_count)
		let used = usedPages * UInt64(pageSize)
		return ProcessInfo.processInfo.physicalMemory > used ? ProcessInfo.processInfo.physicalMemory - used : 0
	}

	static func networkStatistics() -> [NetworkStatistics] {
		var list: UnsafeMutablePointer<ifaddrs>?
		guard getifaddrs(&list) == 0, let first = list else { return [] }
		defer { freeifaddrs(list) }

		var result: [NetworkStatistics] = []
		var current: UnsafeMutablePointer<ifaddrs>? = first
		while let item = current?.pointee {
			defer { current = item.ifa_next }
			guard let address = item.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
			      item.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) != 0,
			      let rawData = item.ifa_data
			else { continue }
			let name = String(cString: item.ifa_name)
			guard name.hasPrefix("lo") == false else { continue }
			let data = rawData.assumingMemoryBound(to: if_data.self).pointee
			guard data.ifi_ibytes >= 20_000_000, data.ifi_obytes >= 2_000_000 else { continue }
			result.append(.init(name: name, received: UInt64(data.ifi_ibytes), sent: UInt64(data.ifi_obytes)))
		}
		return result
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

enum SystemProfilerLocalization {
	static func string(_ key: String, _ arguments: CVarArg...) -> String {
		let bundle = Bundle(for: SystemProfilerPlugin.self)
		let format = bundle.localizedString(forKey: key, value: nil, table: "BasicLanguage")
		return arguments.isEmpty ? format : String(format: format, arguments: arguments)
	}
}
