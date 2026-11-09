//
//  DeviceInfoView.swift
//  wina
//

import Metal
import SwiftUI

// MARK: - Device Information View

struct DeviceInfoView: View {
    @State private var deviceInfo: DeviceInfo?

    var body: some View {
        List {
            if let info = deviceInfo {
                Section("Hardware") {
                    InfoRow(label: "Model", value: info.model)
                    InfoRow(label: "Model Identifier", value: info.modelIdentifier)
                    InfoRow(label: "System Name", value: info.systemName)
                    InfoRow(label: "System Version", value: info.systemVersion)
                    InfoRow(
                        label: "OS Build", value: info.osBuild,
                        info: "Darwin kernel build number.\nUseful for tracking WebKit bugs\nin specific OS builds.")
                }

                Section("Processor") {
                    InfoRow(
                        label: "CPU Cores", value: info.cpuCores,
                        info: "Total logical cores.\niPhone uses ARM big.LITTLE:\nPerformance + Efficiency cores.")
                    InfoRow(
                        label: "Active Cores", value: info.activeCores,
                        info: "Currently active cores.\nMay throttle based on:\nThermal state, Low Power Mode.")
                    InfoRow(
                        label: "GPU", value: info.gpuName,
                        info: "Apple GPU integrated in SoC.\nMetal API supported.\nShared memory with CPU.")
                }

                Section("Memory & Power") {
                    InfoRow(
                        label: "Physical Memory", value: info.physicalMemory,
                        info: "Total device RAM.\nShared between system and apps.\niPhone: 4-8GB typically.")
                    InfoRow(
                        label: "Thermal State", value: info.thermalState,
                        info:
                            "Nominal: Normal operation\nFair: Slightly warm\nSerious: Performance throttled\nCritical: Aggressive throttling"
                    )
                    CapabilityRow(
                        label: "Low Power Mode", supported: info.isLowPowerMode,
                        info: "Settings > Battery toggle.\nReduces CPU/GPU performance.\nDisables background refresh.")
                }

                Section("Display") {
                    InfoRow(
                        label: "Screen Size", value: info.screenSize,
                        info: "Logical size in points.\n1 point = 2-3 pixels depending on device.")
                    InfoRow(
                        label: "Screen Scale", value: info.screenScale,
                        info: "Points to pixels ratio.\n@2x = Retina, @3x = Super Retina.")
                    InfoRow(
                        label: "Native Scale", value: info.nativeScale,
                        info: "Physical pixel density.\nMay differ from Screen Scale\non some devices.")
                    InfoRow(
                        label: "Brightness", value: info.brightness,
                        info: "Current screen brightness.\n0.0 (min) to 1.0 (max).\nUser or auto-brightness controlled.")
                }

                Section("Locale") {
                    InfoRow(label: "Language", value: info.language)
                    InfoRow(label: "Region", value: info.region)
                    InfoRow(label: "Timezone", value: info.timezone)
                }

                Section("Network") {
                    InfoRow(label: "Host Name", value: info.hostName)
                }
            }
        }
        .overlay {
            if deviceInfo == nil {
                ProgressView()
            }
        }
        .navigationTitle(Text(verbatim: "Device Information"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            deviceInfo = await DeviceInfo.load()
        }
    }
}

// MARK: - Device Info Model

struct DeviceInfo: Sendable, Encodable {
    let model: String
    let modelIdentifier: String
    let systemName: String
    let systemVersion: String
    let osBuild: String
    let cpuCores: String
    let activeCores: String
    let physicalMemory: String
    let thermalState: String
    let isLowPowerMode: Bool
    let gpuName: String
    let screenSize: String
    let screenScale: String
    let nativeScale: String
    let brightness: String
    let language: String
    let region: String
    let timezone: String
    let hostName: String

    @MainActor
    static func load() async -> DeviceInfo {
        let device = UIDevice.current
        let locale = Locale.current
        let processInfo = ProcessInfo.processInfo

        // Get screen from active window scene
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let screen = windowScene?.screen
        let traitCollection = windowScene?.traitCollection

        let gpuName = MTLCreateSystemDefaultDevice()?.name ?? "Unknown"
        let osBuild = getOSBuild()

        let memoryGB = Double(processInfo.physicalMemory) / 1_073_741_824
        let memoryString = String(format: "%.1f GB", memoryGB)

        let thermalStateString: String = {
            switch processInfo.thermalState {
            case .nominal: return "Nominal"
            case .fair: return "Fair"
            case .serious: return "Serious"
            case .critical: return "Critical"
            @unknown default: return "Unknown"
            }
        }()

        let brightnessPercent = screen.map { Int($0.brightness * 100) } ?? 0
        let screenBounds = screen?.bounds ?? .zero
        let displayScale = traitCollection?.displayScale ?? 1.0

        return DeviceInfo(
            model: device.model,
            modelIdentifier: getModelIdentifier(),
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            osBuild: osBuild,
            cpuCores: "\(processInfo.processorCount)",
            activeCores: "\(processInfo.activeProcessorCount)",
            physicalMemory: memoryString,
            thermalState: thermalStateString,
            isLowPowerMode: processInfo.isLowPowerModeEnabled,
            gpuName: gpuName,
            screenSize: "\(Int(screenBounds.width)) x \(Int(screenBounds.height)) pt",
            screenScale: "\(displayScale)x",
            nativeScale: screen.map { "\($0.nativeScale)x" } ?? "Unknown",
            brightness: "\(brightnessPercent)%",
            language: locale.language.languageCode?.identifier ?? "Unknown",
            region: locale.region?.identifier ?? "Unknown",
            timezone: TimeZone.current.identifier,
            hostName: processInfo.hostName
        )
    }

    private static func getModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier += String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    private static func getOSBuild() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var build = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &build, &size, nil, 0)
        return String(cString: build)
    }
}
