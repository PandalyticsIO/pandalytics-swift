import Foundation

/// We're using this struct to store attributes of signals that are essentially
/// always the same for a given installation, so we can avoid recomputing them on
/// every signal. This includes things like device model, OS version, locale, etc.
/// 
/// None of this data is personally identifiable on its own.
struct SignalAttributeCache {
    let appVersion: String
    let buildNumber: String
    let osName: String
    let osVersion: String
    let deviceModel: String
    let deviceType: String

    init() {
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        self.osName = Self.osName
        self.osVersion = Self.osVersion
        self.deviceModel = Self.deviceModel
        self.deviceType = Self.deviceType
    }

    private nonisolated static var osName: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #else
        return "unknown"
        #endif
    }

    private nonisolated static var deviceModel: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        if let nullIndex = machine.firstIndex(of: 0) {
            machine = Array(machine[..<nullIndex])
        }
        return String(decoding: machine.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static var deviceType: String {
        #if os(iOS)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return "phone"
        case .pad: return "tablet"
        case .tv: return "tv"
        default: return "unknown"
        }
        #elseif os(macOS)
        return "desktop"
        #elseif os(watchOS)
        return "watch"
        #elseif os(tvOS)
        return "tv"
        #elseif os(visionOS)
        return "headset"
        #else
        return "unknown"
        #endif
    }

    private static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let buildNumber = Self.osBuildNumber

        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion) (build \(buildNumber))"
    }

    private static var osBuildNumber: String {
        var size: size_t = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)

        var data = Data(count: size)
        data.withUnsafeMutableBytes { ptr in
            _ = sysctlbyname("kern.osversion", ptr.baseAddress, &size, nil, 0)
        }

        // Drop trailing null byte if present
        if let last = data.last, last == 0 {
            data.removeLast()
        }

        return String(decoding: data, as: UTF8.self)
    }
}